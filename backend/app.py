import os
from flask import Flask, jsonify

app = Flask(__name__)

APP_NAME    = os.environ.get('APP_NAME',    'Inventario-Default')
APP_VERSION = os.environ.get('APP_VERSION', '1.0')
API_KEY     = os.environ.get('API_KEY',     'no-configurado')

ITEMS = [
    {'id': 1, 'nombre': 'Laptop Dell XPS',    'cantidad': 15, 'precio': 1250.00},
    {'id': 2, 'nombre': 'Monitor LG 27"',     'cantidad':  8, 'precio':  320.00},
    {'id': 3, 'nombre': 'Teclado Mecanico',   'cantidad': 25, 'precio':   95.00},
    {'id': 4, 'nombre': 'Mouse Logitech MX',  'cantidad': 30, 'precio':   75.00},
    {'id': 5, 'nombre': 'Headset Sony WH',    'cantidad': 12, 'precio':  180.00},
]

@app.route('/api/health')
def health():
    return jsonify({
        'status':  'healthy',
        'app':     APP_NAME,
        'version': APP_VERSION
    })

@app.route('/api/items')
def get_items():
    key_configured = API_KEY != 'no-configurado'
    return jsonify({
        'items':   ITEMS,
        'total':   len(ITEMS),
        'key_ok':  key_configured
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
