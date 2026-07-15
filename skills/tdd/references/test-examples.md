# Test examples: good vs bad

Four annotated pairs. Each shows the anti-pattern and the fix for the same
piece of behavior.

## 1. Behavior through the interface vs. implementation-coupled

BAD — mocks an internal collaborator and asserts call counts, not behavior:

```python
def test_checkout_calls_pricing_engine(mocker):
    engine = mocker.patch("cart.PricingEngine")
    checkout(cart_with_items())
    engine.return_value.apply_rules.assert_called_once()
    engine.return_value.apply_rules.assert_called_with(mocker.ANY)
```

Breaks the moment `checkout` is refactored to call the engine differently,
even though checkout still works correctly for the user.

GOOD — behavior through the public interface, one logical assertion:

```python
def test_user_can_checkout_with_valid_cart():
    cart = Cart(items=[Item("book", price=12)])
    receipt = checkout(cart)
    assert receipt.status == "confirmed"
```

Reads like a spec ("user can checkout with valid cart") and survives any
internal refactor of `checkout`, because it never looks inside it.

## 2. Retrieve through the interface vs. interface-bypass

BAD — queries the database directly to verify `create_user` worked:

```python
def test_create_user_writes_row():
    create_user(email="a@example.com", name="Ada")
    row = db.execute("SELECT * FROM users WHERE email = %s", ("a@example.com",))
    assert row[0]["name"] == "Ada"
```

Couples the test to the storage schema; a column rename or table split
breaks the test even though `create_user` still behaves correctly.

GOOD — verifies through the same interface a caller would use:

```python
def test_create_user_then_retrievable():
    create_user(email="a@example.com", name="Ada")
    user = get_user(email="a@example.com")
    assert user.name == "Ada"
```

Only depends on the public contract (`create_user`/`get_user`), so storage
can change shape freely without touching the test.

## 3. Spec literal vs. tautological expected value

BAD — expected value is recomputed the same way the code computes it:

```python
def test_cart_total():
    items = [Item("book", price=10), Item("pen", price=5)]
    expected = sum(i.price for i in items)  # mirrors calculate_total's own logic
    assert calculate_total(items) == expected
```

Passes by construction: if `calculate_total` and the test both sum wrong the
same way, it still goes green.

GOOD — expected value is the literal from the spec's worked example:

```python
def test_cart_total_matches_spec_example():
    items = [Item("book", price=10), Item("pen", price=5)]
    assert calculate_total(items) == 15  # spec's worked example: $10 + $5 = $15
```

The `15` is an independent source of truth, so the test can actually
disagree with a wrong implementation.

## 4. Vertical slice vs. horizontal slicing

BAD — ten tests written up front, no implementation exists yet:

```python
def test_discount_10_percent(): ...
def test_discount_20_percent(): ...
def test_discount_stacking(): ...
def test_discount_expired_code(): ...
# ...six more, all still failing, none driving any code yet
```

Encodes imagined behavior before any seam is proven; most of these tests
will be rewritten once the first real implementation reveals the actual shape.

GOOD — one test drives one minimal implementation, then the next test:

```python
def test_apply_valid_discount_code():
    assert apply_discount(cart_total=100, code="SAVE10") == 90
# implement apply_discount to pass exactly this, then write the next test
```

Each cycle is a tracer bullet: the next test is chosen based on what this
one just taught, instead of a pre-imagined checklist.
