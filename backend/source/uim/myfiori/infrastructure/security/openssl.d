/// Minimal libcrypto prototypes (OpenSSL >= 1.1). libcrypto is already linked through
/// vibe-stream:tls; declaring the few symbols here keeps us independent of binding versions.
module uim.myfiori.infrastructure.security.openssl;

extern (C) nothrow @nogc {
    struct BIO;
    struct EVP_PKEY;
    struct EVP_PKEY_CTX;
    struct EVP_MD_CTX;
    struct EVP_MD;
    struct ENGINE;

    BIO* BIO_new_mem_buf(const(void)* buf, int len);
    int BIO_free(BIO* a);
    EVP_PKEY* PEM_read_bio_PUBKEY(BIO* bp, EVP_PKEY** x, void* cb, void* u);
    void EVP_PKEY_free(EVP_PKEY* pkey);
    EVP_MD_CTX* EVP_MD_CTX_new();
    void EVP_MD_CTX_free(EVP_MD_CTX* ctx);
    const(EVP_MD)* EVP_sha256();
    int EVP_DigestVerifyInit(EVP_MD_CTX* ctx, EVP_PKEY_CTX** pctx, const(EVP_MD)* type, ENGINE* e, EVP_PKEY* pkey);
    int EVP_DigestVerify(EVP_MD_CTX* ctx, const(ubyte)* sig, size_t siglen, const(ubyte)* tbs, size_t tbslen);
    int PKCS5_PBKDF2_HMAC(const(char)* pass, int passlen, const(ubyte)* salt, int saltlen, int iter,
        const(EVP_MD)* digest, int keylen, ubyte* out_);
    int RAND_bytes(ubyte* buf, int num);

    // X.509 inspection (certificate expiry and names for TLS / monitoring)
    struct X509;
    struct X509_NAME;
    struct ASN1_TIME;
    struct ASN1_STRING;
    struct OPENSSL_STACK;
    X509* PEM_read_bio_X509(BIO* bp, X509** x, void* cb, void* u);
    void X509_free(X509* a);
    const(ASN1_TIME)* X509_get0_notAfter(const(X509)* x);
    const(ASN1_TIME)* X509_get0_notBefore(const(X509)* x);
    int ASN1_TIME_diff(int* pday, int* psec, const(ASN1_TIME)* from, const(ASN1_TIME)* to);
    X509_NAME* X509_get_subject_name(const(X509)* a);
    X509_NAME* X509_get_issuer_name(const(X509)* a);
    char* X509_NAME_oneline(const(X509_NAME)* a, char* buf, int size);
    void* X509_get_ext_d2i(const(X509)* x, int nid, int* crit, int* idx);
    int OPENSSL_sk_num(const(OPENSSL_STACK)* st);
    void* OPENSSL_sk_value(const(OPENSSL_STACK)* st, int i);
    void GENERAL_NAMES_free(OPENSSL_STACK* a);
    const(ubyte)* ASN1_STRING_get0_data(const(ASN1_STRING)* x);
    int ASN1_STRING_length(const(ASN1_STRING)* x);
}

enum NID_subject_alt_name = 85;
enum GEN_DNS = 2;

/// layout of OpenSSL's GENERAL_NAME (type + union of pointers)
struct GENERAL_NAME {
    int type;
    void* d;
}

/// Cryptographically secure random bytes.
ubyte[] secureRandom(size_t n) {
    auto buf = new ubyte[n];
    if (RAND_bytes(buf.ptr, cast(int) n) != 1)
        throw new Exception("RAND_bytes failed");
    return buf;
}

/// Compares in constant time (for MACs and hashes).
bool constantTimeEquals(const(ubyte)[] a, const(ubyte)[] b) pure nothrow @nogc @safe {
    if (a.length != b.length)
        return false;
    ubyte diff = 0;
    foreach (i; 0 .. a.length)
        diff |= a[i] ^ b[i];
    return diff == 0;
}

/// Random URL-safe password / secret.
string randomSecret(size_t bytes = 18) {
    import std.base64 : Base64URLNoPadding;
    return Base64URLNoPadding.encode(secureRandom(bytes)).idup;
}
