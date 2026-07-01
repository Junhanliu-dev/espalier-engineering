---
name: espalier-testing
description: Test writing skill matching project's testing patterns
---

# Testing Skill

## Test Framework
{detected framework and assertion style}

## Project Testing Patterns
{how tests are structured in this project — derived from reading actual tests}

## Principles
1. Change-driven: test what you changed, at the boundary of the change
2. Real data preferred: use realistic inputs, not `"test"` / `123`
3. Match existing style: new tests should look like existing tests

## Test File Template
{derived from actual test files in the project}

## Mock/Fixture Conventions
{how this project does mocking — derived from existing tests}

## What to Test
- Every new public function/method
- Every changed public interface
- Edge cases for business logic
- Error paths (not just happy path)

## Security Abuse Tests (when a security contract is present)
When the change has an `espalier/changes/{type}/{slug}/security-record.md` with a
`## Security-Sensitive Fields` contract (from the Stage 4 `harness-security` audit),
write a negative test for EACH field. The shape is always **tamper → assert
rejected → assert persistent store unchanged**:
- tamper the value (foreign id, `$0.01` price, `isAdmin=true`, illegal status)
- assert the request is rejected (403 / 404 / 422 per project convention)
- assert the persisted store did NOT change

A happy-path test does NOT satisfy the contract. See
`espalier/skills/espalier-security/SKILL.md` for the recipe. Enforced at Stage 6 —
a contracted field with no abuse test is a P0.

## What NOT to Test
- Private internals (test via public interface)
- Framework behavior (trust the framework)
- Trivial getters/setters
