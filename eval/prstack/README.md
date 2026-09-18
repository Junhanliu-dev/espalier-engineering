# prstack eval

Scores the Stage 7 doc sweep (`skills/espalier-init/templates/agents/modes/wiki-sweep.md`)
against golden fixtures.

```bash
bash run.sh            # every fixture
bash run.sh 03         # only fixtures whose filename contains "03"
```

Exit codes: `0` gate pass · `1` gate fail · `2` bad setup · `3` infra
(no fixture executed).

Each fixture carries its own world: a diff, the current contents of every wiki
and rule file, and the verdict each of those files must receive. The runner
builds the sweep's prompt from the mode text plus that world, parses the
`### Wiki Sweep` block it returns, and compares verdicts — deterministically.
See `rubric.md` for the two gate classes and `KNOWN-ISSUES.md` for what has
gone wrong here before.

Dev/QA infra. Not shipped to target projects.
