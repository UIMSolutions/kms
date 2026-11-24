/// Business exceptions. The presentation layer maps them to HTTP status codes.
module uim.myfiori.domain.exceptions;

class DomainException : Exception {
    this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

/// 400 - invalid input
class ValidationException : DomainException {
    this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

/// 401 - not authenticated / bad credentials
class UnauthorizedException : DomainException {
    this(string msg = "Authentication required", string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

/// 403 - authenticated but not allowed
class ForbiddenException : DomainException {
    this(string msg = "Not allowed", string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

/// 404
class NotFoundException : DomainException {
    this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

/// 409 - uniqueness or optimistic-locking conflicts
class ConflictException : DomainException {
    this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

/// 413 - upload too large / quota exceeded
class PayloadTooLargeException : DomainException {
    this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}

/// 423 - account temporarily locked
class LockedException : DomainException {
    this(string msg, string file = __FILE__, size_t line = __LINE__) @safe pure nothrow {
        super(msg, file, line);
    }
}
