/// In-memory full-text search engine (inverted index, BM25 ranking).
///
/// Features:
///  - field weights: title x3, tags x2, body / extracted file text x1
///  - query syntax: `term`, `"exact phrase"`, `-excluded`, `prefix*`
///  - AND semantics across query clauses, fuzzy fallback (edit distance) for unknown terms
///    with "did you mean" suggestions
///  - structured filters (kind, space, tag, media kind) and facet counts
///  - highlighted snippets (HTML-escaped, matches in <strong>)
///  - prefix auto-completion over the vocabulary
///
/// The engine is pure domain logic; the application layer keeps it in sync with the
/// repositories (see SearchIndexer) and rebuilds it from the file system on start-up.
module uim.myfiori.domain.services.searchengine;

import std.algorithm : canFind, endsWith, filter, map, max, min, sort, startsWith;
import std.algorithm.comparison : levenshteinDistance;
import std.array : appender, array;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.math : log;
import std.string : strip;
import uim.myfiori.domain.enumerations.itemkind;
import uim.myfiori.domain.services.tokenizer;
import uim.myfiori.domain.types.searchquery;

/// What the engine knows about one searchable item.
struct IndexEntry {
    string id;
    ItemKind kind;
    string title;
    string text;      /// raw body / extracted text (for snippets)
    string summary;   /// fallback snippet
    string[] tags;
    string spaceId;
    string status;    /// article status; "published" for documents
    string mediaKind; /// documents only
    string updatedAt; /// ISO timestamp (sortable)
    string ownerId;
}

private struct Stored {
    IndexEntry entry;
    string[] tokens;   /// title + tags + text tokens (for phrase matching)
    double length;     /// weighted document length
    string[] terms;    /// distinct terms (for removal)
}

enum titleWeight = 3.0;
enum tagWeight = 2.0;
enum maxIndexedTextBytes = 2 * 1024 * 1024;

final class SearchEngine {
    private Stored[string] docs;
    private double[string][string] postings; // term -> (doc id -> weighted tf)
    private double totalLength = 0;
    private enum k1 = 1.2, b = 0.75;

    size_t count() const {
        return docs.length;
    }

    size_t vocabularySize() const {
        return postings.length;
    }

    bool contains(string id) const {
        return (id in docs) !is null;
    }

    void clear() {
        docs = null;
        postings = null;
        totalLength = 0;
    }

    /// Adds or replaces an item.
    void put(IndexEntry e) {
        remove(e.id);
        if (e.text.length > maxIndexedTextBytes)
            e.text = e.text[0 .. maxIndexedTextBytes];
        double[string] tf;
        string[] tokens;
        double len = 0;
        void add(string[] ts, double w) {
            foreach (t; ts) {
                tf[t] = tf.get(t, 0) + w;
                len += w;
            }
            tokens ~= ts;
        }

        add(tokenize(e.title), titleWeight);
        foreach (tag; e.tags)
            add(tokenize(tag), tagWeight);
        add(tokenize(e.summary), 1.5);
        add(tokenize(e.text), 1.0);

        Stored s;
        s.entry = e;
        s.tokens = tokens;
        s.length = len;
        foreach (term, w; tf) {
            postings[term][e.id] = w;
            s.terms ~= term;
        }
        totalLength += len;
        docs[e.id] = s;
    }

    void remove(string id) {
        auto s = id in docs;
        if (s is null)
            return;
        foreach (t; s.terms) {
            if (auto p = t in postings) {
                (*p).remove(id);
                if ((*p).length == 0)
                    postings.remove(t);
            }
        }
        totalLength -= s.length;
        docs.remove(id);
    }

    /// Auto-completion: vocabulary terms with the given prefix (most frequent first)
    /// followed by matching titles.
    string[] suggest(string prefix, size_t limit = 8, scope bool delegate(ref const IndexEntry) visible = null) {
        auto p = normalizeTerm(prefix.strip);
        if (p.length == 0)
            return [];
        struct C {
            string term;
            size_t df;
        }

        C[] cands;
        foreach (term, ref ids; postings)
            if (term.startsWith(p))
                cands ~= C(term, ids.length);
        cands.sort!((x, y) => x.df > y.df || (x.df == y.df && x.term < y.term));
        string[] result;
        foreach (c; cands[0 .. min(limit, cands.length)])
            result ~= c.term;
        // titles whose words start with the prefix
        foreach (id, ref s; docs) {
            if (result.length >= limit * 2)
                break;
            if (visible !is null && !visible(s.entry))
                continue;
            foreach (t; tokenize(s.entry.title))
                if (t.startsWith(p)) {
                    if (!result.canFind(s.entry.title))
                        result ~= s.entry.title;
                    break;
                }
        }
        return result;
    }

    /// Executes a query. `visible` filters items the caller may not see.
    SearchResult search(in SearchQuery q, scope bool delegate(ref const IndexEntry) visible = null) {
        auto sw = StopWatch(AutoStart.yes);
        SearchResult result;
        auto pq = parseQuery(q.text);
        const bool empty = pq.terms.length == 0 && pq.prefixes.length == 0 && pq.phrases.length == 0;

        double[string] scores;
        bool first = true;

        void intersect(double[string] clause) {
            if (first) {
                scores = clause;
                first = false;
                return;
            }
            double[string] next;
            foreach (id, sc; scores)
                if (auto c = id in clause)
                    next[id] = sc + *c;
            scores = next;
        }

        if (empty) {
            foreach (id, ref s; docs)
                scores[id] = 0;
            first = false;
        }
        foreach (term; pq.terms) {
            double[string] clause;
            if (auto p = term in postings)
                addTerm(clause, term, *p, 1.0);
            else {
                // fuzzy fallback
                auto corrections = fuzzyTerms(term);
                foreach (c; corrections)
                    addTerm(clause, c, postings[c], 0.6);
                if (corrections.length)
                    result.suggestions ~= corrections[0];
            }
            intersect(clause);
        }
        foreach (pre; pq.prefixes) {
            double[string] clause;
            size_t n;
            foreach (term, ref ids; postings)
                if (term.startsWith(pre)) {
                    addTerm(clause, term, ids, term == pre ? 1.0 : 0.8);
                    if (++n >= 64)
                        break;
                }
            intersect(clause);
        }
        foreach (phrase; pq.phrases) {
            double[string] clause;
            if (phrase.length == 1) {
                if (auto p = phrase[0] in postings)
                    addTerm(clause, phrase[0], *p, 1.0);
            } else if (auto p = phrase[0] in postings) {
                foreach (id, _; *p) {
                    if (containsSequence(docs[id].tokens, phrase)) {
                        double sc = 0;
                        foreach (t; phrase)
                            if (auto pp = t in postings)
                                if (auto w = id in *pp)
                                    sc += bm25(*w, docs[id].length, (*pp).length);
                        clause[id] = sc * 1.5;
                    }
                }
            }
            intersect(clause);
        }
        foreach (ex; pq.excluded)
            if (auto p = ex in postings)
                foreach (id, _; *p)
                    scores.remove(id);

        // visibility, then facets (before structured filters), then filters
        string[] matched;
        foreach (id, _; scores)
            if (visible is null || visible(docs[id].entry))
                matched ~= id;

        size_t[string] kinds, spaces, tags, media;
        foreach (id; matched) {
            auto e = &docs[id].entry;
            kinds[cast(string) e.kind]++;
            if (e.spaceId.length)
                spaces[e.spaceId]++;
            foreach (t; e.tags)
                tags[t]++;
            if (e.mediaKind.length)
                media[e.mediaKind]++;
        }
        result.kinds = facet(kinds, 10);
        result.spaces = facet(spaces, 20);
        result.tags = facet(tags, 25);
        result.mediaKinds = facet(media, 10);

        auto filtered = matched.filter!((id) {
            auto e = &docs[id].entry;
            return (q.kind.length == 0 || e.kind == q.kind)
                && (q.spaceId.length == 0 || e.spaceId == q.spaceId)
                && (q.tag.length == 0 || e.tags.canFind(q.tag))
                && (q.mediaKind.length == 0 || e.mediaKind == q.mediaKind);
        }).array;

        if (empty)
            filtered.sort!((x, y) => docs[x].entry.updatedAt > docs[y].entry.updatedAt);
        else
            filtered.sort!((x, y) => scores[x] > scores[y]
                    || (scores[x] == scores[y] && docs[x].entry.updatedAt > docs[y].entry.updatedAt));

        result.total = filtered.length;
        auto top = q.top == 0 ? 20 : min(q.top, 200);
        auto start = min(q.skip, filtered.length);
        auto end = min(start + top, filtered.length);
        auto highlight = highlightTerms(pq);
        foreach (id; filtered[start .. end]) {
            auto e = &docs[id].entry;
            SearchHit h;
            h.id = e.id;
            h.kind = e.kind;
            h.title = e.title;
            h.score = scores[id];
            h.spaceId = e.spaceId;
            h.tags = e.tags.dup;
            h.status = e.status;
            h.mediaKind = e.mediaKind;
            h.updatedAt = e.updatedAt;
            h.snippet = makeSnippet(e.text.length ? e.text : e.summary, highlight, pq.prefixes);
            if (h.snippet.length == 0 && e.summary.length)
                h.snippet = makeSnippet(e.summary, highlight, pq.prefixes);
            result.hits ~= h;
        }
        result.tookMicros = sw.peek.total!"usecs";
        return result;
    }

    // ------------------------------------------------------------------ internals

    private double bm25(double tf, double docLen, size_t df) const {
        const n = cast(double) docs.length;
        const avg = docs.length ? totalLength / n : 1.0;
        const idf = log(1.0 + (n - df + 0.5) / (df + 0.5));
        return idf * (tf * (k1 + 1)) / (tf + k1 * (1 - b + b * docLen / (avg > 0 ? avg : 1)));
    }

    private void addTerm(ref double[string] clause, string term, ref double[string] ids, double factor) {
        foreach (id, w; ids) {
            auto sc = bm25(w, docs[id].length, ids.length) * factor;
            if (auto c = id in clause)
                *c = max(*c, sc);
            else
                clause[id] = sc;
        }
    }

    /// Vocabulary terms within edit distance 1 (>= 4 chars) or 2 (>= 8 chars), most frequent first.
    private string[] fuzzyTerms(string term) {
        if (term.length < 4)
            return [];
        const maxDist = term.length >= 8 ? 2 : 1;
        struct C {
            string t;
            size_t d;
            size_t df;
        }

        C[] cands;
        foreach (t, ref ids; postings) {
            if (t.length + maxDist < term.length || t.length > term.length + maxDist)
                continue;
            auto d = levenshteinDistance(t, term);
            if (d <= maxDist)
                cands ~= C(t, d, ids.length);
        }
        cands.sort!((x, y) => x.d < y.d || (x.d == y.d && x.df > y.df));
        return cands.map!(c => c.t).array[0 .. min(5, cands.length)];
    }

    private static bool containsSequence(const string[] tokens, const string[] seq) {
        if (seq.length == 0 || tokens.length < seq.length)
            return false;
        outer: foreach (i; 0 .. tokens.length - seq.length + 1) {
            foreach (j, s; seq)
                if (tokens[i + j] != s)
                    continue outer;
            return true;
        }
        return false;
    }

    private static FacetValue[] facet(size_t[string] counts, size_t limit) {
        FacetValue[] r;
        foreach (k, v; counts)
            r ~= FacetValue(k, v);
        r.sort!((x, y) => x.count > y.count || (x.count == y.count && x.value < y.value));
        return r[0 .. min(limit, r.length)];
    }

    private string[] highlightTerms(in ParsedQuery pq) {
        string[] t = pq.terms.dup;
        foreach (term; pq.terms)
            if (term !in postings)
                t ~= fuzzyTerms(term);
        foreach (p; pq.phrases)
            t ~= p;
        return t;
    }
}

/// Parses the query syntax into clauses.
ParsedQuery parseQuery(string text) {
    ParsedQuery pq;
    size_t i = 0;
    while (i < text.length) {
        while (i < text.length && (text[i] == ' ' || text[i] == '\t' || text[i] == '\n'))
            i++;
        if (i >= text.length)
            break;
        bool negate = false;
        if (text[i] == '-' && i + 1 < text.length && text[i + 1] != ' ') {
            negate = true;
            i++;
        }
        if (text[i] == '"') {
            auto end = i + 1;
            while (end < text.length && text[end] != '"')
                end++;
            auto toks = tokenize(text[i + 1 .. end]);
            i = end + 1;
            if (toks.length == 0)
                continue;
            if (negate)
                pq.excluded ~= toks;
            else
                pq.phrases ~= toks;
            continue;
        }
        auto end = i;
        while (end < text.length && text[end] != ' ' && text[end] != '\t' && text[end] != '\n')
            end++;
        auto word = text[i .. end];
        i = end;
        bool prefix = word.endsWith("*");
        if (prefix)
            word = word[0 .. $ - 1];
        if (negate) {
            foreach (t; tokenize(word))
                pq.excluded ~= t;
            continue;
        }
        if (prefix) {
            // no stemming for prefixes: "documents*" should still match "documents..."
            auto spans = tokenSpans(word);
            if (spans.length) {
                foreach (s; spans[0 .. $ - 1])
                    if (s.term.length)
                        pq.terms ~= s.term;
                auto last = normalizeTerm(word[spans[$ - 1].start .. spans[$ - 1].end]);
                if (last.length)
                    pq.prefixes ~= last;
            }
            continue;
        }
        auto spans = tokenSpans(word);
        if (spans.length == 1) {
            // single word: keep even stop words if it is the only thing the user typed
            auto t = spans[0].term.length ? spans[0].term : normalizeTerm(word);
            if (t.length)
                pq.terms ~= t;
        } else if (spans.length > 1) {
            auto toks = tokenize(word);
            if (toks.length > 1)
                pq.phrases ~= toks; // "e-mail" -> phrase [e, mail]
            else if (toks.length == 1)
                pq.terms ~= toks[0];
        }
    }
    return pq;
}

/// HTML escaping for snippets.
string escapeHtml(string s) {
    auto o = appender!string;
    foreach (char c; s) {
        switch (c) {
        case '<':
            o ~= "&lt;";
            break;
        case '>':
            o ~= "&gt;";
            break;
        case '&':
            o ~= "&amp;";
            break;
        case '"':
            o ~= "&quot;";
            break;
        case '\'':
            o ~= "&#39;";
            break;
        default:
            o ~= c;
        }
    }
    return o[];
}

/// Builds a ~240 character snippet around the first match; matches are wrapped in <strong>.
string makeSnippet(string text, const string[] terms, const string[] prefixes, size_t radius = 110) {
    if (text.length == 0)
        return "";
    auto spans = tokenSpans(text);
    bool isMatch(ref const TokenSpan s) {
        if (s.term.length == 0)
            return false;
        if (terms.canFind(s.term))
            return true;
        foreach (p; prefixes)
            if (s.term.startsWith(p))
                return true;
        return false;
    }

    size_t center = 0;
    foreach (ref s; spans)
        if (isMatch(s)) {
            center = s.start;
            break;
        }
    size_t from = center > radius ? center - radius : 0;
    size_t to = min(text.length, from + 2 * radius);
    // align to UTF-8 boundaries
    while (from > 0 && (text[from] & 0xC0) == 0x80)
        from--;
    while (to < text.length && (text[to] & 0xC0) == 0x80)
        to++;
    // and to word boundaries
    foreach (ref s; spans)
        if (s.start < from && s.end > from) {
            from = s.end;
            break;
        }
    auto o = appender!string;
    if (from > 0)
        o ~= "… ";
    size_t pos = from;
    foreach (ref s; spans) {
        if (s.end <= from)
            continue;
        if (s.start >= to)
            break;
        if (s.end > to)
            break;
        if (isMatch(s)) {
            o ~= escapeHtml(collapse(text[pos .. s.start]));
            o ~= "<strong>" ~ escapeHtml(text[s.start .. s.end]) ~ "</strong>";
            pos = s.end;
        }
    }
    if (pos < to)
        o ~= escapeHtml(collapse(text[pos .. to]));
    if (to < text.length)
        o ~= " …";
    return o[].strip;
}

/// collapses line breaks / runs of whitespace and Markdown markers into single spaces
private string collapse(string s) {
    auto o = appender!string;
    bool ws = false;
    foreach (char c; s) {
        if (c == '\n' || c == '\r' || c == '\t' || c == ' ' || c == '#' || c == '*' || c == '`' || c == '|') {
            if (!ws)
                o ~= ' ';
            ws = true;
        } else {
            o ~= c;
            ws = false;
        }
    }
    return o[];
}

unittest {
    auto se = new SearchEngine;
    se.put(IndexEntry("a1", ItemKind.article, "Onboarding guide", "How to set up your laptop and VPN access.",
            "", ["hr", "it"], "s1", "published", "", "2026-01-01"));
    se.put(IndexEntry("a2", ItemKind.article, "VPN troubleshooting", "If the VPN client fails, restart the service.",
            "", ["it"], "s2", "draft", "", "2026-02-01"));
    se.put(IndexEntry("d1", ItemKind.document, "Travel policy.pdf", "Travel expenses are reimbursed within 30 days.",
            "", ["finance"], "s1", "published", "document", "2026-03-01"));

    auto r = se.search(SearchQuery("vpn"));
    assert(r.total == 2);
    assert(r.hits[0].id == "a2"); // title match ranks first
    assert(r.hits[1].snippet.canFind("<strong>VPN</strong>"));

    // visibility
    r = se.search(SearchQuery("vpn"), (ref const IndexEntry e) => e.status == "published");
    assert(r.total == 1 && r.hits[0].id == "a1");

    // phrase / exclusion / prefix / fuzzy
    assert(se.search(SearchQuery(`"restart the service"`)).total == 1);
    assert(se.search(SearchQuery("vpn -laptop")).total == 1);
    assert(se.search(SearchQuery("reimb*")).total == 1);
    auto f = se.search(SearchQuery("travl"));
    assert(f.total == 1 && f.suggestions == ["travel"]);

    // filters and facets
    SearchQuery q;
    q.text = "vpn";
    q.spaceId = "s1";
    r = se.search(q);
    assert(r.total == 1 && r.spaces.length == 2);
    q = SearchQuery.init;
    q.kind = "document";
    assert(se.search(q).total == 1);

    // remove
    se.remove("a1");
    assert(se.search(SearchQuery("laptop")).total == 0);
    assert(se.suggest("vp").canFind("vpn"));
    assert(escapeHtml("<b>") == "&lt;b&gt;");
}
