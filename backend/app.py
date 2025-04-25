#app.py
from flask import Flask, request, session, jsonify
from werkzeug.security import check_password_hash
import boto3, uuid

app = Flask(__name__,
            static_folder='../frontend',
            static_url_path='/')
app.secret_key = 'CAMBIA_POR_UN_SECRETO_FUERTE'
app.config['SESSION_TYPE'] = 'filesystem'

dynamo    = boto3.resource('dynamodb', region_name='us-east-1')
admins    = dynamo.Table('Admins')
productos = dynamo.Table('Productos')

# — Login Admin —
@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    resp = admins.get_item(Key={'email': data['email']})
    if 'Item' not in resp or not check_password_hash(resp['Item']['password'], data['password']):
        return jsonify({'error':'Credenciales inválidas'}), 401
    session['admin'] = data['email']
    return jsonify({'message':'ok'})

@app.route('/api/logout')
def logout():
    session.clear()
    return jsonify({})

def auth_required(f):
    from functools import wraps
    @wraps(f)
    def wrapper(*args, **kwargs):
        if 'admin' not in session:
            return jsonify({'error':'no autorizado'}), 401
        return f(*args, **kwargs)
    return wrapper

# — CRUD Productos —
@app.route('/api/productos', methods=['GET'])
def list_prod():
    return jsonify(productos.scan()['Items'])

@app.route('/api/productos', methods=['POST'])
@auth_required
def create_prod():
    d = request.json
    item = {
        'id':       str(uuid.uuid4()),
        'nombre':   d['nombre'],
        'album':    d['album'],
        'autor':    d['autor'],
        'link':     d['link'],
        'precio':   d['precio'],
        'cantidad': d['cantidad']
    }
    productos.put_item(Item=item)
    return jsonify(item), 201

@app.route('/api/productos/<id>', methods=['PUT'])
@auth_required
def upd_prod(id):
    d = request.json
    expr = "SET nombre=:n, album=:a, autor=:u, link=:l, precio=:p, cantidad=:c"
    vals = {':n':d['nombre'], ':a':d['album'], ':u':d['autor'],
            ':l':d['link'],   ':p':d['precio'], ':c':d['cantidad']}
    productos.update_item(Key={'id':id},
                          UpdateExpression=expr,
                          ExpressionAttributeValues=vals)
    return jsonify({}), 204

@app.route('/api/productos/<id>', methods=['DELETE'])
@auth_required
def del_prod(id):
    productos.delete_item(Key={'id':id})
    return jsonify({}), 204

# — Comprar (decrementa cantidad) —
@app.route('/api/comprar/<id>', methods=['POST'])
def comprar(id):
    productos.update_item(
        Key={'id':id},
        UpdateExpression="SET cantidad = cantidad - :d",
        ConditionExpression="cantidad > :z",
        ExpressionAttributeValues={':d':1,':z':0}
    )
    return jsonify({}), 200

# — Rutas estáticas —
@app.route('/', defaults={'path':''})
@app.route('/<path:path>')
def front(path):
    return app.send_static_file(path or 'index.html')

if __name__=='__main__':
    app.run(host='0.0.0.0', port=3000)
