# crdt_lf_recipes

Private, unpublished package (`publish_to: none`) with the recipes and the merge
traces that the docs site and the READMEs show. Its tests run in CI.

## Recipes

A recipe is a complete use case: its files, a test that runs it, and a YAML
descriptor in `recipes/`. The docs site reads it with `<Recipe>` and
`<RecipeSnippet>`. `melos run recipes_sync` copies it where the workspace asks
for it: a README block (`<!-- recipe:… -->`) or a package example (`copyTo` in
the descriptor). CI fails when a copy differs (`melos run recipes_check`).

## Traces

A trace plays an edge case that must merge well (inserts at one spot, add and
remove, moves) on real documents. A test fails when the peers disagree after a
sync, or when `traces/<id>.json`, what each peer reads, changes. `<MergeTrace>`
shows it, step by step, on the site. `recipes_sync` never writes a trace: after
a wanted change, run `fvm flutter test --update-goldens test/traces_test.dart`.
