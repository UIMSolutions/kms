# Developer notes

## Adding a feature: checklist

1. **Domain**: add or extend entities / value types and keep rules I/O-free (`domain/`).
2. **Port**: describe the use case in `ports/usecases`; add driven ports if new infrastructure is needed.
3. **Application**: implement the interactor in `application/usecases`, with DTOs in `application/dtos`.
4. **Persistence**: add a record, a mapper and a `Storage*Repository` (collection name in `Collections`).
5. **Presentation**: add a controller in `presentation/http` and register it in `composition.d`.
6. **Frontend**: add a route in `manifest.json`, a view + controller, and i18n texts (EN and DE).
7. **Tests**: add inline `unittest` blocks and extend `tests/integration.d`.

## Search engine

`domain/services/searchengine.d` is pure and unit-tested. `application/services/searchindexer.d` maps
entities to `IndexEntry`. Text extraction (`infrastructure/clients/textextractor.d`) runs in
`TextExtractionWorker` after the `document.uploaded` event. To support a new file format, add a
case to `CompositeTextExtractor.extract`.

## Storage format

Records are the structs in `persistence/records`. All fields are `@optional`, so new fields stay
backward compatible. To migrate data, read the old JSON files in a CLI command and write them again
through the repositories.
