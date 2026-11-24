/// Paging parameters for list use cases.
module uim.myfiori.domain.types.page;

struct PageRequest {
    size_t skip;
    size_t top = 100;
    string filter; /// free text filter on title / name
    string orderBy;
}

struct Page(T) {
    T[] items;
    size_t total;
}

/// Applies skip/top to a slice.
T[] slicePage(T)(T[] all, size_t skip, size_t top) {
    if (skip >= all.length)
        return [];
    auto end = top == 0 ? all.length : (skip + top > all.length ? all.length : skip + top);
    return all[skip .. end];
}
