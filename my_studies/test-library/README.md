# Test library

Master copies of the tests that were changed for the validation studies
(Val2–Val4). `setup-study.bat` uses them: for every test folder in a study's
`tests/` that also exists here, it copies these files over the study's copy
before adding the beeps. Tests not in the library are left as they are.

Only changed files are kept here (each test's `.pbl` and its English
translation); everything else comes from the PEBL battery copy in the study.
The `.pbl` files have **no beeps** — `setup-study.bat` adds them.

| Test | Changes |
|---|---|
| `vsearch` | Repeat/start choice screen after the practice; the target stays up until a mouse click, then the search display appears |
| `TNT` | Mouse choice screen (repeat practice / start real test) replaces the "press a key" screen after the practice |
| `maze` | Repeat/start choice screen after the practice maze |
| `ptrails` | One short practice trial per trail type (1-2-3-4, A-B-C-D, 1-A-2-B) before the real test, then the choice screen |
| `tol` | 3 easy 3-disc practice problems (1, 2, 3 moves, not in the real set), then the choice screen |

To change a test for all future studies, edit it here, then re-run
`setup-study.bat` in each study that should get the change. Translations other
than English fall back to the English text for the new screens.
