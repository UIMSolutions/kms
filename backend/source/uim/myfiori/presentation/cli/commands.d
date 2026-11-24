/// Administrative commands, e.g. `kms-backend user-add anna user 'S3cret-Passw0rd'`.
module uim.myfiori.presentation.cli.commands;

import std.algorithm.searching : canFind;
import std.stdio : writeln, writefln, stderr;
import uim.myfiori.application.dtos;
import uim.myfiori.domain;
import uim.myfiori.ports;

final class AdminCli {
    private static immutable commands = ["help", "user-list", "user-add", "user-passwd", "user-role", "reindex"];

    private UserUseCase users;
    private UserRepository userRepo;
    private SearchUseCase search;

    this(UserUseCase users, UserRepository userRepo, SearchUseCase search) {
        this.users = users;
        this.userRepo = userRepo;
        this.search = search;
    }

    static bool isCommand(string[] args) {
        return args.length > 1 && commands.canFind(args[1]);
    }

    /// The CLI acts as a built-in administrator.
    private static Principal system() {
        return Principal("cli", "cli", "Command line", Role.admin);
    }

    int run(string[] args) {
        try {
            switch (args[1]) {
            case "user-list":
                foreach (u; users.list(system, PageRequest(0, 0)).items)
                    writefln("%-20s %-8s %-6s %s", u.username, u.role, u.active ? "active" : "off", u.displayName);
                return 0;
            case "user-add":
                if (args.length < 5)
                    return usage();
                UserInput i;
                i.username = args[2];
                i.role = args[3];
                i.password = args[4];
                i.mustChangePassword = false;
                auto u = users.create(system, i);
                writefln("created user %s (%s)", u.username, u.role);
                return 0;
            case "user-passwd":
                if (args.length < 4)
                    return usage();
                users.resetPassword(system, requireUser(args[2]), args[3]);
                writefln("password of %s changed", args[2]);
                return 0;
            case "user-role":
                if (args.length < 4)
                    return usage();
                UserInput i;
                i.role = args[3];
                auto u = users.update(system, requireUser(args[2]), i);
                writefln("%s is now %s", u.username, u.role);
                return 0;
            case "reindex":
                writefln("indexed %s items", search.reindex(system));
                return 0;
            default:
                return usage();
            }
        } catch (Exception e) {
            stderr.writeln("error: ", e.msg);
            return 1;
        }
    }

    private string requireUser(string name) {
        auto u = userRepo.byUsername(name);
        if (u is null)
            throw new NotFoundException("no such user: " ~ name);
        return u.id;
    }

    private static int usage() {
        writeln("usage: kms-backend <command>\n"
                ~ "  user-list\n"
                ~ "  user-add <username> <user|admin> <password>\n"
                ~ "  user-passwd <username> <password>\n"
                ~ "  user-role <username> <user|admin>\n"
                ~ "  reindex\n"
                ~ "without a command the HTTP server starts");
        return 2;
    }
}
