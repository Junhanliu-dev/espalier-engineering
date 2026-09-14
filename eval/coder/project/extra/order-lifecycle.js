// Order lifecycle predicates — the only way service code asks "is this
// order finished?". CLOSED and CANCELLED are both terminal.
const TERMINAL_STATUSES = Object.freeze(['CLOSED', 'CANCELLED']);

function isTerminal(order) {
  return TERMINAL_STATUSES.includes(order.status);
}

module.exports = { isTerminal, TERMINAL_STATUSES };
