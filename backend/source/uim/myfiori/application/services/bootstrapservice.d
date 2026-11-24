/// First start: creates the initial administrator and optional demo content.
module uim.myfiori.application.services.bootstrapservice;

import uim.myfiori.application.services.searchindexer;
import uim.myfiori.domain;
import uim.myfiori.ports;

struct BootstrapSettings {
    string adminUser = "admin";
    string adminPassword;   /// generated when empty
    bool demoContent = true;
}

struct BootstrapResult {
    bool performed;
    string generatedPassword;
}

final class BootstrapService {
    private UserRepository users;
    private SpaceRepository spaces;
    private ArticleRepository articles;
    private PasswordHasher hasher;
    private Clock clock;
    private IdGenerator ids;

    this(UserRepository users, SpaceRepository spaces, ArticleRepository articles, PasswordHasher hasher,
        Clock clock, IdGenerator ids) {
        this.users = users;
        this.spaces = spaces;
        this.articles = articles;
        this.hasher = hasher;
        this.clock = clock;
        this.ids = ids;
    }

    BootstrapResult run(BootstrapSettings s, string delegate() generatePassword) {
        BootstrapResult r;
        if (users.count() > 0)
            return r;
        r.performed = true;
        const now = clock.now;
        auto admin = new User;
        admin.id = ids.newId;
        admin.username = validUsername(s.adminUser);
        admin.displayName = "Administrator";
        admin.role = Role.admin;
        auto pw = s.adminPassword;
        if (pw.length == 0) {
            pw = generatePassword();
            r.generatedPassword = pw;
            admin.mustChangePassword = true;
        }
        admin.passwordHash = hasher.hash(pw);
        admin.createdAt = admin.updatedAt = now;
        users.save(admin);

        if (s.demoContent && spaces.all().length == 0)
            seedDemo(admin.id);
        return r;
    }

    private void seedDemo(string adminId) {
        const now = clock.now;
        Space mk(string key, string name, string desc, string icon) {
            auto sp = new Space;
            sp.id = ids.newId;
            sp.key = key;
            sp.name = name;
            sp.description = desc;
            sp.icon = icon;
            sp.createdBy = adminId;
            sp.createdAt = sp.updatedAt = now;
            spaces.save(sp);
            return sp;
        }

        auto general = mk("GEN", "General", "Company-wide knowledge, policies and how-tos", "sap-icon://course-book");
        auto it = mk("IT", "IT & Tools", "Guides for systems, tools and troubleshooting", "sap-icon://it-system");

        void art(Space sp, string title, string summary, string body, string[] tags) {
            auto a = new Article;
            a.id = ids.newId;
            a.spaceId = sp.id;
            a.title = title;
            a.summary = summary;
            a.body = body;
            a.tags = tags;
            a.authorId = adminId;
            a.updatedBy = adminId;
            a.createdAt = a.updatedAt = now;
            a.publish(now);
            articles.save(a);
        }

        art(general, "Welcome to the Knowledge Base",
            "What the knowledge management system offers and how to get started.",
            "# Welcome\n\nThis knowledge base collects **articles**, **documents** and other **media** "
            ~ "in *spaces*.\n\n## Getting started\n\n- Browse the spaces in the navigation\n"
            ~ "- Use the search field to find articles and file contents\n"
            ~ "- Editors can create articles and upload documents\n\n"
            ~ "Administrators manage users and spaces.", ["welcome", "getting-started"]);
        art(general, "Search tips",
            "Query syntax of the full-text search engine.",
            "# Search tips\n\n| Syntax | Meaning |\n|---|---|\n| `vpn client` | both words |\n"
            ~ "| `\"exact phrase\"` | words in this order |\n| `-draft` | exclude a word |\n"
            ~ "| `config*` | prefix search |\n\nTypos are corrected automatically (fuzzy matching). "
            ~ "Results can be filtered by type, space, tag and media kind. The search covers titles, tags, "
            ~ "article text and the text extracted from uploaded PDF, Office and text files.",
            ["search", "help"]);
        art(it, "VPN access for remote work",
            "How to install and configure the VPN client.",
            "# VPN access\n\n1. Install the VPN client from the software portal\n"
            ~ "2. Sign in with your company account\n3. Select the nearest gateway\n\n"
            ~ "## Troubleshooting\n\nIf the connection fails, restart the client and check your network.",
            ["vpn", "remote-work", "network"]);
    }
}
