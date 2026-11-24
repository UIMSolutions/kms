/// Driven ports for business data access (implemented in persistence/repositories).
module uim.myfiori.ports.repositories;

import uim.myfiori.domain.entities;

interface UserRepository {
    User[] all();
    User byId(string id);          /// null if missing
    User byUsername(string name);  /// null if missing
    User byExternalId(string ext); /// null if missing
    void save(User u);
    void remove(string id);
    size_t count();
}

interface SpaceRepository {
    Space[] all();
    Space byId(string id);
    Space byKey(string key);
    void save(Space s);
    void remove(string id);
}

interface MembershipRepository {
    Membership[] all();
    Membership[] bySpace(string spaceId);
    Membership[] byUser(string userId);
    Membership find(string spaceId, string userId); /// null if missing
    void save(Membership m);
    void remove(string id);
}

interface ArticleRepository {
    Article[] all();
    Article byId(string id);
    Article[] bySpace(string spaceId);
    void save(Article a);
    void remove(string id);
}

interface ArticleVersionRepository {
    ArticleVersion[] byArticle(string articleId); /// newest first
    ArticleVersion byId(string id);
    void save(ArticleVersion v);
    void remove(string id);
    void removeByArticle(string articleId);
}

interface DocumentRepository {
    Document[] all();
    Document byId(string id);
    Document[] bySpace(string spaceId);
    void save(Document d);
    void remove(string id);
}
