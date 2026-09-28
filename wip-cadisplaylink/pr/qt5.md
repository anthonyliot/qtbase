# qt5 superproject

`wip/cadisplaylink` on git@github.com:anthonyliot/qt5.git only moves the `qtbase` and
`qtdeclarative` submodule pointers to the `wip/cadisplaylink` branches, and sets `branch =
wip/cadisplaylink` for those two in `.gitmodules` (the URLs stay relative, `../qtbase.git`, so a
clone of the fork resolves to the forked submodules). All its commits are `WIP:` and are dropped
when upstreaming; Qt's dependency update commits take care of the pointers.
