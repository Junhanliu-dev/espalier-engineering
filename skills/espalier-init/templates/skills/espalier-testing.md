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

## What NOT to Test
- Private internals (test via public interface)
- Framework behavior (trust the framework)
- Trivial getters/setters
