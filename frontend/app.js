// frontend/app.js - Frontend JavaScript for interacting with the API
let loggedIn = false;
let editProductId = null;

// Helper to fetch and display product list
function loadProducts() {
  fetch('/api/products')
    .then(res => res.json())
    .then(products => {
      const list = document.getElementById('product-list');
      list.innerHTML = '';
      products.forEach(prod => {
        const item = document.createElement('li');
        item.textContent = `${prod.name} - $${prod.price}`;
        if (loggedIn) {
          // Add edit and delete controls for admin
          const editBtn = document.createElement('button');
          editBtn.textContent = 'Editar';
          editBtn.onclick = () => startEditProduct(prod);
          const delBtn = document.createElement('button');
          delBtn.textContent = 'Eliminar';
          delBtn.onclick = () => deleteProduct(prod.id);
          item.appendChild(document.createTextNode(' '));
          item.appendChild(editBtn);
          item.appendChild(document.createTextNode(' '));
          item.appendChild(delBtn);
        }
        list.appendChild(item);
      });
      if (products.length === 0) {
        list.innerHTML = '<li>No hay productos disponibles</li>';
      }
    });
}

// Attempt login
document.getElementById('login-form').addEventListener('submit', function(e) {
  e.preventDefault();
  const email = document.getElementById('email').value;
  const pwd = document.getElementById('password').value;
  fetch('/api/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: email, password: pwd }),
    credentials: 'same-origin'
  })
    .then(res => {
      if (res.ok) {
        loggedIn = true;
        document.getElementById('login-section').style.display = 'none';
        document.getElementById('admin-section').style.display = 'block';
        document.getElementById('login-msg').textContent = '';
        // If logged in, enable admin controls and refresh product list to show buttons
        loadProducts();
      } else {
        loggedIn = false;
        document.getElementById('login-msg').textContent = 'Credenciales inválidas';
      }
    });
});

// Add or update product
document.getElementById('product-form').addEventListener('submit', function(e) {
  e.preventDefault();
  const nameInput = document.getElementById('prod-name');
  const priceInput = document.getElementById('prod-price');
  const name = nameInput.value;
  const price = priceInput.value;
  const method = editProductId ? 'PUT' : 'POST';
  const url = editProductId ? '/api/products/' + editProductId : '/api/products';
  fetch(url, {
    method: method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: name, price: price }),
    credentials: 'same-origin'
  })
    .then(res => res.json())
    .then(data => {
      if (data.error) {
        document.getElementById('form-msg').textContent = data.error;
      } else {
        // Reset form and message
        nameInput.value = '';
        priceInput.value = '';
        document.getElementById('form-msg').textContent = '';
        if (editProductId) {
          // Finished editing
          document.getElementById('product-form').querySelector('button[type=submit]').textContent = 'Agregar Producto';
          document.getElementById('cancel-edit').style.display = 'none';
          editProductId = null;
        }
        // Refresh list
        loadProducts();
      }
    });
});

// Cancel edit
document.getElementById('cancel-edit').addEventListener('click', function() {
  document.getElementById('prod-name').value = '';
  document.getElementById('prod-price').value = '';
  document.getElementById('product-form').querySelector('button[type=submit]').textContent = 'Agregar Producto';
  document.getElementById('cancel-edit').style.display = 'none';
  editProductId = null;
  document.getElementById('form-msg').textContent = '';
});

// Start editing a product (populate form)
function startEditProduct(prod) {
  editProductId = prod.id;
  document.getElementById('prod-name').value = prod.name;
  document.getElementById('prod-price').value = prod.price;
  document.getElementById('product-form').querySelector('button[type=submit]').textContent = 'Actualizar Producto';
  document.getElementById('cancel-edit').style.display = 'inline';
}

// Delete a product
function deleteProduct(id) {
  if (!confirm('¿Eliminar este producto?')) return;
  fetch('/api/products/' + id, { method: 'DELETE', credentials: 'same-origin' })
    .then(res => {
      if (res.ok) {
        loadProducts();
      } else {
        alert('Error al eliminar el producto');
      }
    });
}

// Initial load of products list
loadProducts();
