/// Background queue for full-text extraction of uploaded files: uploads return immediately,
/// the text becomes searchable a moment later.
module uim.myfiori.infrastructure.workers.textextractionworker;

import vibe.core.core : runTask, Task, yield;
import vibe.core.sync : LocalManualEvent, createManualEvent;
import vibe.core.log;
import uim.myfiori.application.services.textextraction;
import uim.myfiori.ports.messaging;

final class TextExtractionWorker : EventHandler {
    private TextExtractionService service;
    private string[] queue;
    private LocalManualEvent signal;
    private Task task;
    private bool running;
    private bool synchronous; // tests / CLI: process immediately

    this(TextExtractionService service, bool synchronous = false) {
        this.service = service;
        this.synchronous = synchronous;
        signal = createManualEvent();
    }

    void handle(in DomainEvent e) {
        if (e.type != "document.uploaded")
            return;
        if (synchronous || !running) {
            service.process(e.subjectId);
            return;
        }
        queue ~= e.subjectId;
        signal.emit();
    }

    /// Queues all given documents (e.g. after start-up for not yet extracted files).
    void enqueue(string[] ids) {
        queue ~= ids;
        if (running)
            signal.emit();
    }

    size_t pending() const {
        return queue.length;
    }

    void start() {
        running = true;
        task = runTask(() nothrow {
            while (running) {
                try {
                    if (queue.length == 0) {
                        auto c = signal.emitCount;
                        signal.wait(c);
                        continue;
                    }
                    auto id = queue[0];
                    queue = queue[1 .. $];
                    service.process(id);
                    yield();
                } catch (Exception e) {
                    logError("text extraction worker: %s", e.msg);
                }
            }
        });
    }

    void stop() {
        running = false;
        signal.emit();
    }
}
