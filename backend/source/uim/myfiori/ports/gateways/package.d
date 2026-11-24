/// Driven ports for external tools and third-party systems.
module uim.myfiori.ports.gateways;

/// Extracts searchable plain text from a file (PDF, Office, text formats ...).
interface TextExtractor {
    /// Returns the text or "" if the format is not supported.
    string extract(string fileName, string mimeType, const(ubyte)[] data);
}
