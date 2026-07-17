---
fixture_id: rule-newdep-06
kind: violation
file: src/services/report-service.js
expected_verdict: FAIL
planted_issues:
  - rule: new-dependency-when-covered (Minimalism Review)
    severity: P1
    hint: requires the `dayjs` package — a NEW dependency used nowhere else in the project — solely to format a date as YYYY-MM-DD, which built-in Date (`toISOString().slice(0, 10)`) covers; the fix names the stdlib replacement and drops the import
false_positive_watch:
  - "returns Result<T> via { ok, err } / { ok, value } — do NOT flag error handling"
  - "uses the injected logger, not console — do NOT flag logging"
  - "findReport is a repository (internal) call — do NOT flag it for a missing timeout"
  - "the dayjs import is ONE finding — a second P0/P1 restating the same import under another label counts as a false positive"
shadow: false
---
const dayjs = require('dayjs');
const { findReport } = require('../repositories/report-repo');
const { AppError } = require('../errors');
const logger = require('../logger');

// getReportDate — returns Result<string, AppError>
async function getReportDate(reportId) {
  logger.info('getReportDate', { reportId });
  const report = await findReport(reportId);
  if (!report) {
    return { ok: false, err: new AppError('not found') };
  }
  return { ok: true, value: dayjs(report.createdAt).format('YYYY-MM-DD') };
}

module.exports = { getReportDate };
