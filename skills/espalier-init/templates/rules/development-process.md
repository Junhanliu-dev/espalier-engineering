# Development Process

## Branch Strategy
{detected from git or CI config}

## Commit Conventions
{detected from git log}

## CI Checks
{existing checks + what they verify}

## Deploy & Verification
{from DISCOVERY.deploy — mechanism, exact command (or "automatic on merge"),
health check, and which environment a merged change reaches. This is what
pipeline Stage 9 runs/verifies. If DISCOVERY.deploy was null, write exactly:
"No deploy configuration discovered — Stage 9 records SKIPPED: no-deploy-config."}

## Quality Bar
{what must pass before merge — derived from CI + project conventions}
