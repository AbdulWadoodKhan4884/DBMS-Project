from flask import Flask, render_template, request, redirect, url_for, flash, session
import psycopg2
from psycopg2 import sql
from dotenv import load_dotenv
import os

load_dotenv()

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", "your-secret-key-here")

# Database connection configuration
DB_CONFIG = {
    "dbname": os.getenv("DB_NAME", "your_db_name"),
    "user": os.getenv("DB_USER", "your_db_user"),
    "password": os.getenv("DB_PASSWORD", "your_db_password"),
    "host": os.getenv("DB_HOST", "localhost"),
    "port": os.getenv("DB_PORT", "5432"),
}


def get_db_connection():
    conn = psycopg2.connect(**DB_CONFIG)
    return conn


@app.route("/clearCart")
def clear_cart():
    """Route to clear the current user's cart"""
    if "customer_id" not in session:
        return redirect(url_for("register_customer"))

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            "DELETE FROM Orders WHERE customer_id = %s AND status = 'cart'",
            (session["customer_id"],),
        )
        conn.commit()
        flash("Cart cleared successfully", "success")
    except Exception as e:
        conn.rollback()
        flash(f"Error clearing cart: {e}", "error")
    finally:
        cur.close()
        conn.close()
    return redirect(url_for("product_catalogue"))


@app.route("/", methods=["GET", "POST"])
def register_customer():
    if request.method == "POST":
        # Extract form data
        first_name = request.form["first_name"]
        last_name = request.form["last_name"]
        email = request.form["email"]
        phone = request.form.get("phone", "")
        address = request.form.get("address", "")
        city = request.form.get("city", "")
        state = request.form.get("state", "")
        country = request.form.get("country", "")
        customer_tier = request.form.get("customer_tier", "regular")

        # Insert customer into database
        conn = get_db_connection()
        cur = conn.cursor()
        try:
            cur.execute(
                sql.SQL(
                    """
                    INSERT INTO Customers (first_name, last_name, email, phone, address, city, state, country, tier, password_hash)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """
                ),
                (
                    first_name,
                    last_name,
                    email,
                    phone,
                    address,
                    city,
                    state,
                    country,
                    customer_tier,
                    "dummy_password",
                ),
            )
            conn.commit()

            # Get the newly created customer_id
            cur.execute(
                "SELECT currval(pg_get_serial_sequence('customers','customer_id'))"
            )
            customer_id = cur.fetchone()[0]
            session["customer_id"] = customer_id
            return redirect(url_for("product_catalogue"))
        except Exception as e:
            conn.rollback()
            flash(f"Error inserting customer: {e}", "error")
            return render_template(
                "regCustomer.html", error="Registration failed. Please try again."
            )
        finally:
            cur.close()
            conn.close()
    return render_template("regCustomer.html")


@app.route("/prodCatalogue", methods=["GET", "POST"])
def product_catalogue():
    if "customer_id" not in session:
        return redirect(url_for("register_customer"))

    if request.method == "POST":
        product_id = request.form.get("product_id")
        quantity = int(request.form.get("quantity", 1))

        conn = get_db_connection()
        cur = conn.cursor()
        try:
            # Check inventory
            cur.execute(
                "SELECT quantity_in_stock, reserved_quantity FROM Inventory WHERE product_id = %s",
                (product_id,),
            )
            stock_data = cur.fetchone()

            if not stock_data:
                flash("Product not found in inventory", "error")
                return redirect(url_for("product_catalogue"))

            available = stock_data[0] - stock_data[1]
            if quantity > available:
                flash(f"Only {available} items available in stock", "error")
                return redirect(url_for("product_catalogue"))

            # Get existing cart
            cur.execute(
                """
                SELECT order_id, items, quantities 
                FROM Orders 
                WHERE customer_id = %s AND status = 'cart'
                LIMIT 1
                """,
                (session["customer_id"],),
            )
            cart = cur.fetchone()

            if cart:
                order_id, items, quantities = cart
                items = list(items) if items else []
                quantities = list(quantities) if quantities else []

                try:
                    index = items.index(int(product_id))
                    quantities[index] = quantity
                except ValueError:
                    items.append(int(product_id))
                    quantities.append(quantity)

                cur.execute(
                    """
                    UPDATE Orders 
                    SET items = %s::integer[], quantities = %s::integer[]
                    WHERE order_id = %s
                    """,
                    (items, quantities, order_id),
                )
            else:
                cur.execute(
                    """
                    INSERT INTO Orders (
                        customer_id, 
                        status, 
                        items, 
                        quantities, 
                        shipping_address, 
                        shipping_city, 
                        shipping_country
                    )
                    VALUES (
                        %s, 'cart', 
                        %s::integer[], 
                        %s::integer[], 
                        'Default Address', 
                        'Default City', 
                        'Default Country'
                    )
                    RETURNING order_id
                    """,
                    (
                        session["customer_id"],
                        [int(product_id)],
                        [quantity],
                    ),
                )
                order_id = cur.fetchone()[0]

            conn.commit()
            flash(f"Added {quantity} item(s) to cart", "success")
        except Exception as e:
            conn.rollback()
            flash(f"Error updating cart: {e}", "error")
        finally:
            cur.close()
            conn.close()

        return redirect(url_for("product_catalogue"))

    # GET request handling
    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT p.product_id, p.name, p.description, p.category, p.price, p.image_path, 
                   i.quantity_in_stock, i.reserved_quantity
            FROM Products p
            JOIN Inventory i ON p.product_id = i.product_id
            """
        )
        products = []
        for row in cur.fetchall():
            product = {
                "id": row[0],
                "name": row[1],
                "description": row[2],
                "category": row[3],
                "price": float(row[4]),
                "image_path": row[5],
                "in_stock": row[6] - row[7],
            }
            products.append(product)
    except Exception as e:
        flash(f"Error fetching products: {e}", "error")
        products = []
    finally:
        cur.close()
        conn.close()

    return render_template("prodCatalogue.html", products=products)


@app.route("/cartPage")
def cart_page():
    if "customer_id" not in session:
        return redirect(url_for("register_customer"))

    conn = get_db_connection()
    cur = conn.cursor()
    shipping = 0.0
    try:
        cur.execute(
            """
            SELECT o.items, o.quantities, 
                   ARRAY_AGG(p.name ORDER BY array_position(o.items, p.product_id)),
                   ARRAY_AGG(p.description ORDER BY array_position(o.items, p.product_id)),
                   ARRAY_AGG(p.category ORDER BY array_position(o.items, p.product_id)),
                   ARRAY_AGG(p.price ORDER BY array_position(o.items, p.product_id)),
                   ARRAY_AGG(p.image_path ORDER BY array_position(o.items, p.product_id))
            FROM Orders o
            JOIN Products p ON p.product_id = ANY(o.items)
            WHERE o.customer_id = %s AND o.status = 'cart'
            GROUP BY o.order_id, o.items, o.quantities
            """,
            (session["customer_id"],),
        )
        cart_data = cur.fetchone()

        cart_items = []
        subtotal = 0.0

        if cart_data and len(cart_data) == 7:
            items = cart_data[0] if cart_data[0] else []
            quantities = cart_data[1] if cart_data[1] else []
            names = cart_data[2] if cart_data[2] else []
            descriptions = cart_data[3] if cart_data[3] else []
            categories = cart_data[4] if cart_data[4] else []
            prices = cart_data[5] if cart_data[5] else []
            image_paths = cart_data[6] if cart_data[6] else []

            item_count = min(len(items), len(quantities), len(prices))
            for i in range(item_count):
                try:
                    quantity = int(quantities[i]) if quantities[i] else 0
                    price = float(prices[i]) if prices[i] else 0.0
                    item_total = price * quantity
                    subtotal += item_total

                    cart_items.append(
                        {
                            "id": items[i],
                            "name": names[i] if i < len(names) else "Unknown Product",
                            "description": (
                                descriptions[i] if i < len(descriptions) else ""
                            ),
                            "category": categories[i] if i < len(categories) else "",
                            "price": price,
                            "quantity": quantity,
                            "item_total": item_total,
                            "image_path": (
                                image_paths[i] if i < len(image_paths) else ""
                            ),
                        }
                    )
                except (ValueError, TypeError) as e:
                    print(f"Error processing cart item {i}: {e}")
                    continue

        shipping = 5.99
        total = subtotal + shipping

    except Exception as e:
        flash(f"Error fetching cart: {e}", "error")
        cart_items = []
        subtotal = 0.0
        shipping = 0.0
        total = 0.0
    finally:
        cur.close()
        conn.close()

    return render_template(
        "cartPage.html",
        cart_items=cart_items,
        subtotal=subtotal,
        shipping=shipping,
        total=total,
    )


@app.route("/confirmOrder", methods=["GET", "POST"])
def confirm_order():
    if "customer_id" not in session:
        print("[DEBUG] Customer not in session, redirecting to register.")
        return redirect(url_for("register_customer"))

    if request.method == "POST":
        print("[DEBUG] Handling POST request for order confirmation.")
        payment_method = request.form["payment_method"]
        shipping_address = request.form["shipping_address"]
        shipping_city = request.form["shipping_city"]
        shipping_state = request.form.get("shipping_state", "")
        shipping_country = request.form["shipping_country"]
        extra_notes = request.form.get("extra_notes", "")

        conn = get_db_connection()
        cur = conn.cursor()
        shipping = 0.0

        try:
            print("[DEBUG] Updating Orders table for status 'confirmed'")
            cur.execute(
                """
                UPDATE Orders 
                SET status = 'confirmed',
                    payment_method = %s,
                    shipping_address = %s,
                    shipping_city = %s,
                    shipping_state = %s,
                    shipping_country = %s,
                    notes = %s,
                    order_date = CURRENT_TIMESTAMP
                WHERE customer_id = %s AND status = 'cart'
                RETURNING order_id, items, quantities
                """,
                (
                    payment_method,
                    shipping_address,
                    shipping_city,
                    shipping_state,
                    shipping_country,
                    extra_notes,
                    session["customer_id"],
                ),
            )

            order_info = cur.fetchone()
            print(f"[DEBUG] Order info fetched: {order_info}")

            if order_info:
                order_id, items, quantities = order_info

                print("[DEBUG] Calculating subtotal for order items.")
                cur.execute(
                    """
                    SELECT SUM(p.price * q.quantity)
                    FROM Products p
                    JOIN UNNEST(%s::int[], %s::int[]) AS q(product_id, quantity)
                    ON p.product_id = q.product_id
                    """,
                    (items, quantities),
                )

                subtotal = cur.fetchone()[0] or 0
                print(f"[DEBUG] Subtotal calculated: {subtotal}")

                shipping = 5.99
                total_amount = float(subtotal) + shipping

                print(f"[DEBUG] Updating Orders with total amount: {total_amount}")
                cur.execute(
                    """
                    UPDATE Orders 
                    SET total_amount = %s
                    WHERE order_id = %s
                    """,
                    (total_amount, order_id),
                )

                print(f"[DEBUG] Reserving inventory for each item.")
                for product_id, quantity in zip(items, quantities):
                    print(
                        f"[DEBUG] Reserving product_id={product_id}, quantity={quantity}"
                    )
                    cur.execute(
                        """
                        UPDATE Inventory
                        SET reserved_quantity = reserved_quantity + %s
                        WHERE product_id = %s
                        """,
                        (quantity, product_id),
                    )

                print("[DEBUG] Appending order_id to customer orders.")
                cur.execute(
                    """
                    UPDATE Customers
                    SET orders = array_append(orders, %s)
                    WHERE customer_id = %s
                    """,
                    (order_id, session["customer_id"]),
                )

            else:
                print("[DEBUG] No order found with status 'cart'.")
                raise Exception("No order found to confirm.")

            conn.commit()
            print("[DEBUG] Order confirmed and committed.")
            # flash("Order confirmed successfully!", "success")
            return redirect(url_for("checkout_page"))

        except Exception as e:
            print(f"[ERROR] Exception occurred: {e}")
            conn.rollback()
            flash(f"Error confirming order: {e}", "error")

            return render_template(
                "confirmOrder.html",
                error="Order confirmation failed. Please try again.",
                order_items=[],
                subtotal=0,
                shipping=0,
                total=0,
            )

        finally:
            cur.close()
            conn.close()
            print("[DEBUG] Database connection closed after POST.")

    # GET request handling
    print("[DEBUG] Handling GET request for confirm order page.")
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute(
            """
            SELECT o.items, o.quantities, 
                   ARRAY_AGG(p.name), ARRAY_AGG(p.description), ARRAY_AGG(p.category), 
                   ARRAY_AGG(p.price), ARRAY_AGG(p.image_path)
            FROM Orders o
            JOIN Products p ON p.product_id = ANY(o.items)
            WHERE o.customer_id = %s AND o.status = 'cart'
            GROUP BY o.order_id, o.items, o.quantities
            """,
            (session["customer_id"],),
        )

        cart_data = cur.fetchone()
        print(f"[DEBUG] Cart data fetched: {cart_data}")

        if cart_data:
            items, quantities, names, descriptions, categories, prices, image_paths = (
                cart_data
            )
            order_items = []
            subtotal = 0

            for i in range(len(items)):
                item_total = float(prices[i]) * quantities[i]
                subtotal += item_total

                order_items.append(
                    {
                        "id": items[i],
                        "name": names[i],
                        "description": descriptions[i],
                        "category": categories[i],
                        "price": float(prices[i]),
                        "quantity": quantities[i],
                        "item_total": item_total,
                        "image_path": image_paths[i],
                    }
                )

            shipping = 5.99
            total = subtotal + shipping
        else:
            print("[DEBUG] No items in cart.")
            order_items = []
            subtotal = 0
            shipping = 0
            total = 0

    except Exception as e:
        print(f"[ERROR] Error fetching cart details: {e}")
        flash(f"Error fetching order details: {e}", "error")
        order_items = []
        subtotal = 0
        shipping = 0
        total = 0

    finally:
        cur.close()
        conn.close()
        print("[DEBUG] Database connection closed after GET.")

    return render_template(
        "confirmOrder.html",
        order_items=order_items,
        subtotal=subtotal,
        shipping=shipping,
        total=total,
    )


@app.route("/checkoutPage")
def checkout_page():
    if "customer_id" not in session:
        return redirect(url_for("register_customer"))

    conn = get_db_connection()
    cur = conn.cursor()
    try:
        cur.execute(
            """
            SELECT o.order_id, o.order_date, o.items, o.quantities, o.total_amount,
                   o.shipping_address, o.shipping_city, o.shipping_state, o.shipping_country,
                   o.payment_method, o.notes,
                   ARRAY_AGG(p.name), ARRAY_AGG(p.description), ARRAY_AGG(p.category), 
                   ARRAY_AGG(p.price), ARRAY_AGG(p.image_path)
            FROM Orders o
            JOIN Products p ON p.product_id = ANY(o.items)
            WHERE o.customer_id = %s AND o.status = 'confirmed'
            GROUP BY o.order_id
            ORDER BY o.order_date DESC
            LIMIT 1
            """,
            (session["customer_id"],),
        )
        order_data = cur.fetchone()

        if order_data:
            (
                order_id,
                order_date,
                items,
                quantities,
                total_amount,
                shipping_address,
                shipping_city,
                shipping_state,
                shipping_country,
                payment_method,
                notes,
                names,
                descriptions,
                categories,
                prices,
                image_paths,
            ) = order_data

            order_items = []

            for i in range(len(items)):
                order_items.append(
                    {
                        "id": items[i],
                        "name": names[i],
                        "description": descriptions[i],
                        "category": categories[i],
                        "price": float(prices[i]),
                        "quantity": quantities[i],
                        "item_total": float(prices[i]) * quantities[i],
                        "image_path": image_paths[i],
                    }
                )

            order_details = {
                "order_id": order_id,
                "order_date": order_date,
                "total_amount": float(total_amount),
                "shipping_address": shipping_address,
                "shipping_city": shipping_city,
                "shipping_state": shipping_state,
                "shipping_country": shipping_country,
                "payment_method": payment_method,
                "notes": notes,
                "items": order_items,
            }
            return redirect(url_for("order_complete"))
        return render_template("checkoutPage.html", order=order_details)
    except Exception as e:
        flash(f"Error fetching order details: {e}", "error")
        order_details = None
    finally:
        cur.close()
        conn.close()

    return render_template("checkoutPage.html", order=order_details)


@app.route("/orderComplete")
def order_complete():
    if "customer_id" not in session:
        return redirect(url_for("register_customer"))
    return render_template("orderComplete.html")


if __name__ == "__main__":
    app.run(debug=True)
