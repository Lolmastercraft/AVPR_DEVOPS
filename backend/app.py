# backend/app.py - Flask application (API for products and admin login)
from flask import Flask, request, jsonify, session
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash
import os

app = Flask(__name__)
# Configure database connection from environment variables
DB_HOST = os.environ.get('DB_HOST', '')
DB_NAME = os.environ.get('DB_NAME', '')
DB_USER = os.environ.get('DB_USER', '')
DB_PASS = os.environ.get('DB_PASS', '')
if not all([DB_HOST, DB_NAME, DB_USER, DB_PASS]):
    raise RuntimeError("Database configuration is not set in environment variables")

app.config['SQLALCHEMY_DATABASE_URI'] = f"mysql+mysqldb://{DB_USER}:{DB_PASS}@{DB_HOST}/{DB_NAME}"
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
# Set secret key for session management
app.secret_key = "supersecretkey"

db = SQLAlchemy(app)

# Define database models
class Admin(db.Model):
    __tablename__ = 'Admins'
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(128), nullable=False)

class Product(db.Model):
    __tablename__ = 'Productos'
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(200), nullable=False)
    price = db.Column(db.Float, nullable=False)

# Create tables if they don't exist and ensure initial admin user
with app.app_context():
    db.create_all()
    # Check if initial admin exists
    admin = Admin.query.filter_by(email="adminpro@gmail.com").first()
    if not admin:
        # Create initial admin user with password "hola"
        hashed_pw = generate_password_hash("hola")
        new_admin = Admin(email="adminpro@gmail.com", password_hash=hashed_pw)
        db.session.add(new_admin)
        db.session.commit()

# Utility: check if current session is logged in as admin
def is_logged_in():
    return session.get('admin_logged_in', False)

# Route: Admin login
@app.route('/api/login', methods=['POST'])
def login():
    data = request.get_json()
    if not data or 'email' not in data or 'password' not in data:
        return jsonify({"error": "Email and password required"}), 400
    email = data['email']
    password = data['password']
    admin = Admin.query.filter_by(email=email).first()
    if not admin or not check_password_hash(admin.password_hash, password):
        return jsonify({"error": "Invalid credentials"}), 401
    # Set session flag
    session['admin_logged_in'] = True
    return jsonify({"message": "Login successful"})

# Route: List products (public)
@app.route('/api/products', methods=['GET'])
def list_products():
    products = Product.query.all()
    # Serialize products to list of dict
    output = []
    for prod in products:
        output.append({"id": prod.id, "name": prod.name, "price": prod.price})
    return jsonify(output)

# Route: Create product (admin only)
@app.route('/api/products', methods=['POST'])
def create_product():
    if not is_logged_in():
        return jsonify({"error": "Unauthorized"}), 401
    data = request.get_json()
    if not data or 'name' not in data or 'price' not in data:
        return jsonify({"error": "Name and price are required"}), 400
    name = data['name']
    price = data['price']
    try:
        price_val = float(price)
    except ValueError:
        return jsonify({"error": "Price must be a number"}), 400
    new_prod = Product(name=name, price=price_val)
    db.session.add(new_prod)
    db.session.commit()
    return jsonify({"message": "Product created", "product": {"id": new_prod.id, "name": new_prod.name, "price": new_prod.price}}), 201

# Route: Update product (admin only)
@app.route('/api/products/<int:prod_id>', methods=['PUT'])
def update_product(prod_id):
    if not is_logged_in():
        return jsonify({"error": "Unauthorized"}), 401
    data = request.get_json()
    product = Product.query.get_or_404(prod_id)
    # Update fields if provided
    if 'name' in data:
        product.name = data['name']
    if 'price' in data:
        try:
            product.price = float(data['price'])
        except ValueError:
            return jsonify({"error": "Price must be a number"}), 400
    db.session.commit()
    return jsonify({"message": "Product updated"})

# Route: Delete product (admin only)
@app.route('/api/products/<int:prod_id>', methods=['DELETE'])
def delete_product(prod_id):
    if not is_logged_in():
        return jsonify({"error": "Unauthorized"}), 401
    product = Product.query.get_or_404(prod_id)
    db.session.delete(product)
    db.session.commit()
    return jsonify({"message": "Product deleted"})
