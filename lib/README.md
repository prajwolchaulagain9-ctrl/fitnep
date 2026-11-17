# Code folder template

`app/` is reserved for application setup, navigation, and theme.
`core/` is reserved for shared infrastructure and utilities.
`shared/` is reserved for models, providers, and widgets used by multiple features.

Each feature has this layout:

```text
feature/
  data/
    datasources/
    models/
    repositories/
  domain/
    entities/
    repositories/
    usecases/
  presentation/
    controllers/
    pages/
    widgets/
```

Folders and new Dart files are placeholders only. No feature code has been
implemented. Start with the files needed for the current feature; the empty
directories do not require empty classes or a use case for every method.
