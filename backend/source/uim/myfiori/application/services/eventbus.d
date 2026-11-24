/// Synchronous in-process event bus (implements the EventPublisher port).
module uim.myfiori.application.services.eventbus;

import vibe.core.log;
import uim.myfiori.ports.messaging;

final class EventBus : EventPublisher {
    private EventHandler[] handlers;

    void subscribe(EventHandler h) {
        handlers ~= h;
    }

    void publish(DomainEvent e) {
        foreach (h; handlers) {
            try
                h.handle(e);
            catch (Exception ex)
                logWarn("event handler failed for %s: %s", e.type, ex.msg);
        }
    }
}
