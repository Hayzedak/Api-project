from flask import Flask, jsonify
import datetime

app = Flask(__name__)

@app.route('/', methods=['GET'])
def get_time():
    current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return jsonify({"current_time": current_time})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)