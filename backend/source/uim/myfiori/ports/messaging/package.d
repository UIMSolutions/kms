/// Driven / driving ports for domain events.
module uim.myfiori.ports.messaging;

import std.datetime.systime : SysTime;

struct DomainEvent {
    string type;      /// e.g. "article.published", "document.uploaded", "user.login"
    string subjectId;
    string actorId;
    string detail;
    SysTime at;
}

interface EventPublisher {
    void publish(DomainEvent e);
}

interface EventHandler {
    void handle(in DomainEvent e);
}
