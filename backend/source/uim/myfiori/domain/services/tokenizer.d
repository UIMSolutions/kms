/// Text analysis for the search engine: Unicode-aware tokenizing, case and diacritics
/// folding, stop-word removal (English & German) and a light plural stemmer.
module uim.myfiori.domain.services.tokenizer;

import std.array : appender;
import std.uni : isAlpha, isNumber, toLower;
import std.utf : decode, encode;

/// A token with its byte range in the source text.
struct TokenSpan {
    size_t start;
    size_t end;
    string term; /// normalized; empty for stop words
}

enum maxTokenLength = 64;

private immutable bool[string] stopWords;

shared static this() {
    bool[string] s;
    foreach (w; [
            // English
            "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "he", "in", "is", "it",
            "its", "of", "on", "or", "that", "the", "to", "was", "were", "will", "with", "this", "these",
            "those", "but", "not", "if", "into", "than", "then", "there", "their", "they", "which", "who",
            // German
            "der", "die", "das", "den", "dem", "des", "ein", "eine", "einer", "eines", "einem", "einen",
            "und", "oder", "ist", "sind", "war", "im", "in", "zu", "zum", "zur", "mit", "von", "fur", "auf",
            "als", "auch", "es", "sie", "er", "wir", "ihr", "nicht", "bei", "aus", "wie", "dass", "an", "am",
            "nach", "noch", "nur", "so", "um", "wird", "werden", "kann", "sich", "uber"
        ])
        s[w] = true;
    stopWords = cast(immutable) s;
}

/// Folds case and common Latin diacritics ("Über" -> "uber", "ß" -> "ss").
void foldChar(dchar c, ref dchar[] outBuf) {
    c = toLower(c);
    switch (c) {
    case 'ä', 'à', 'á', 'â', 'ã', 'å', 'ā':
        outBuf ~= 'a';
        break;
    case 'ö', 'ò', 'ó', 'ô', 'õ', 'ø':
        outBuf ~= 'o';
        break;
    case 'ü', 'ù', 'ú', 'û':
        outBuf ~= 'u';
        break;
    case 'é', 'è', 'ê', 'ë':
        outBuf ~= 'e';
        break;
    case 'í', 'ì', 'î', 'ï':
        outBuf ~= 'i';
        break;
    case 'ç':
        outBuf ~= 'c';
        break;
    case 'ñ':
        outBuf ~= 'n';
        break;
    case 'ß':
        outBuf ~= "ss"d;
        break;
    default:
        outBuf ~= c;
    }
}

/// Light stemmer: strips plural / genitive "s" ("documents" -> "document").
string stem(string t) pure @safe {
    if (t.length > 3 && t[$ - 1] == 's' && t[$ - 2] != 's' && t[$ - 2] != 'u' && t[$ - 2] != 'i')
        return t[0 .. $ - 1];
    return t;
}

private string finish(dchar[] buf) {
    auto o = appender!string;
    foreach (c; buf)
        o.put(c);
    return o[];
}

/// Splits text into token spans (stop words get an empty `term`).
TokenSpan[] tokenSpans(string text) {
    TokenSpan[] spans;
    dchar[] buf;
    size_t start = size_t.max;
    size_t i = 0;
    void flush(size_t end) {
        if (start == size_t.max)
            return;
        string t = finish(buf);
        buf.length = 0;
        if (t.length <= maxTokenLength) {
            string term = (t in stopWords) ? "" : stem(t);
            spans ~= TokenSpan(start, end, term);
        }
        start = size_t.max;
    }

    while (i < text.length) {
        size_t pos = i;
        dchar c;
        try
            c = decode(text, i);
        catch (Exception) {
            i = pos + 1;
            flush(pos);
            continue;
        }
        if (isAlpha(c) || isNumber(c)) {
            if (start == size_t.max)
                start = pos;
            foldChar(c, buf);
        } else
            flush(pos);
    }
    flush(text.length);
    return spans;
}

/// Normalized terms without stop words.
string[] tokenize(string text) {
    string[] terms;
    foreach (s; tokenSpans(text))
        if (s.term.length)
            terms ~= s.term;
    return terms;
}

/// Normalizes a single query word (no stop-word removal: a user searching "die" means it).
string normalizeTerm(string word) {
    dchar[] buf;
    foreach (dchar c; word)
        if (isAlpha(c) || isNumber(c))
            foldChar(c, buf);
    return stem(finish(buf));
}

unittest {
    assert(tokenize("Die Bücher-Dokumente der Straße") == ["bucher", "dokumente", "strasse"]);
    assert(tokenize("Searching documents, fast!") == ["searching", "document", "fast"]);
    auto spans = tokenSpans("Hi Wörld");
    assert(spans.length == 2 && spans[1].start == 3 && spans[1].term == "world");
    assert(normalizeTerm("Größe") == "grosse");
}
