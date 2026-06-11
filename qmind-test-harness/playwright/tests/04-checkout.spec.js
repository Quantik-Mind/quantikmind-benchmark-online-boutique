const { test, expect } = require('@playwright/test');

async function addFirstProductToCart(page) {
  await page.goto('/', { waitUntil: 'domcontentloaded' });

  await page.locator('a[href*="/product"]').first().click();

  const addToCartButton = page.getByRole('button', { name: /add/i });
  await expect(addToCartButton).toBeVisible();

  await addToCartButton.click();

  await expect(page.locator('body')).toContainText(/Cart|Shipping Address|Place Order/i);
}

test('checkout-page-accessible-from-cart', async ({ page }) => {
  await addFirstProductToCart(page);

  await expect(page).toHaveURL(/\/cart/);
  await expect(page.locator('body')).toContainText(/Cart/i);
  await expect(page.locator('body')).toContainText(/Shipping Address/i);
  await expect(page.locator('body')).toContainText(/Payment Method/i);
  await expect(page.locator('body')).toContainText(/Place Order/i);
});

test('checkout-form-fields-visible', async ({ page }) => {
  await addFirstProductToCart(page);

  await expect(page.locator('body')).toContainText(/E-mail Address/i);
  await expect(page.locator('body')).toContainText(/Street Address/i);
  await expect(page.locator('body')).toContainText(/Zip Code/i);
  await expect(page.locator('body')).toContainText(/City/i);
  await expect(page.locator('body')).toContainText(/Country/i);
  await expect(page.locator('body')).toContainText(/Credit Card Number/i);
  await expect(page.locator('body')).toContainText(/CVV/i);
});

test('checkout-empty-cart-does-not-complete-order', async ({ page }) => {
  await page.goto('/cart', { waitUntil: 'domcontentloaded' });

  await expect(page.locator('body')).not.toContainText(/order complete|thank you/i);
});

