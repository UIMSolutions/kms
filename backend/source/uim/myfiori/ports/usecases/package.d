/// Driving ports: the use cases offered to the presentation layer.
module uim.myfiori.ports.usecases;

import uim.myfiori.application.dtos;
import uim.myfiori.domain.types;

interface AuthUseCase {
    LoginResult login(string username, string password);
    UserDto me(in Principal p);
    void changePassword(in Principal p, string oldPassword, string newPassword);
    UserDto updateProfile(in Principal p, ProfileInput input);
}

interface UserUseCase {
    Page!UserDto list(in Principal p, PageRequest page);
    UserDto get(in Principal p, string id);
    UserDto create(in Principal p, UserInput input);
    UserDto update(in Principal p, string id, UserInput input);
    void resetPassword(in Principal p, string id, string newPassword);
    void unlock(in Principal p, string id);
    void remove(in Principal p, string id);
    /// minimal user list for picking members / managers (managers and administrators)
    DirectoryEntryDto[] directory(in Principal p, string query);
    /// areas and roles of a user (administrators, or the user himself)
    AssignmentDto[] assignments(in Principal p, string userId);
}

interface SpaceUseCase {
    SpaceDto[] list(in Principal p);
    SpaceDto get(in Principal p, string id);
    SpaceDto create(in Principal p, SpaceInput input);
    SpaceDto update(in Principal p, string id, SpaceInput input);
    void remove(in Principal p, string id);
    SpaceDto setManager(in Principal p, string id, string userId);
    MemberDto[] members(in Principal p, string id);
    MemberDto setMember(in Principal p, string id, string userId, string role);
    void removeMember(in Principal p, string id, string userId);
}

interface ArticleUseCase {
    Page!ArticleDto list(in Principal p, ArticleFilter filter);
    ArticleDto get(in Principal p, string id, bool countView = false);
    ArticleDto create(in Principal p, ArticleInput input);
    ArticleDto update(in Principal p, string id, ArticleInput input, long expectedVersion = 0);
    ArticleDto publish(in Principal p, string id);
    ArticleDto archive(in Principal p, string id);
    ArticleDto reopen(in Principal p, string id);
    ArticleVersionDto[] versions(in Principal p, string id);
    ArticleDto restore(in Principal p, string id, string versionId);
    void remove(in Principal p, string id);
}

interface DocumentUseCase {
    Page!DocumentDto list(in Principal p, DocumentFilter filter);
    DocumentDto get(in Principal p, string id);
    DocumentDto upload(in Principal p, UploadInput input, const(ubyte)[] data);
    DocumentDto replaceFile(in Principal p, string id, string fileName, string mimeType, const(ubyte)[] data);
    DocumentDto update(in Principal p, string id, DocumentInput input);
    FileContent content(in Principal p, string id);
    void remove(in Principal p, string id);
}

interface SearchUseCase {
    SearchResultDto search(in Principal p, SearchQuery q);
    string[] suggest(in Principal p, string prefix);
    size_t reindex(in Principal p);
}

interface StatisticsUseCase {
    StatsDto stats(in Principal p);
}
