// Order status constants — the only way service code names a status.
const ORDER_STATUS = Object.freeze({
  placed: 'placed',
  shipped: 'shipped',
  cancelled: 'cancelled',
});

module.exports = { ORDER_STATUS };
