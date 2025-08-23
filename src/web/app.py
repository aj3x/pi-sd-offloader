#!/usr/bin/env python3
"""
Web interface for Pi SD Offloader - handles user confirmations and configuration.
"""

import os
import json
import yaml
import logging
from datetime import datetime
from flask import Flask, render_template, request, jsonify, send_from_directory
from flask_socketio import SocketIO, emit
from threading import Lock
import time

# Global state management
app = Flask(__name__)
app.config['SECRET_KEY'] = 'pi-sd-offloader-secret'
socketio = SocketIO(app, cors_allowed_origins="*")

# Global state
current_state = {
    'status': 'idle',  # idle, detecting, confirming, transferring, complete, error
    'device_info': {},
    'transfer_progress': {},
    'pending_confirmation': None,
    'settings': {}
}
state_lock = Lock()

def load_settings():
    """Load settings from configuration file."""
    try:
        with open('/etc/pi-sd-offloader/camera_config.yaml', 'r') as f:
            config = yaml.safe_load(f)
        return config.get('settings', {})
    except Exception as e:
        logging.error(f"Failed to load settings: {e}")
        return {}

def save_settings(settings):
    """Save settings to configuration file."""
    try:
        config_path = '/etc/pi-sd-offloader/camera_config.yaml'
        
        # Load existing config
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        # Update settings
        config['settings'] = settings
        
        # Save back
        with open(config_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False)
        
        return True
    except Exception as e:
        logging.error(f"Failed to save settings: {e}")
        return False

@app.route('/')
def index():
    """Main dashboard page."""
    return render_template('index.html')

@app.route('/settings')
def settings_page():
    """Settings configuration page."""
    return render_template('settings.html')

@app.route('/api/status')
def get_status():
    """Get current system status."""
    with state_lock:
        return jsonify(current_state)

@app.route('/api/settings', methods=['GET'])
def get_settings():
    """Get current settings."""
    settings = load_settings()
    return jsonify(settings)

@app.route('/api/settings', methods=['POST'])
def update_settings():
    """Update settings."""
    try:
        new_settings = request.json
        
        # Validate required fields
        required_fields = ['transfer_mode', 'local_storage_path', 'nas_storage_path']
        for field in required_fields:
            if field not in new_settings.get('transfer_settings', {}):
                return jsonify({'error': f'Missing required field: {field}'}), 400
        
        if save_settings(new_settings):
            # Update global state
            with state_lock:
                current_state['settings'] = new_settings
            
            return jsonify({'success': True})
        else:
            return jsonify({'error': 'Failed to save settings'}), 500
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/confirm_transfer', methods=['POST'])
def confirm_transfer():
    """Handle user confirmation for transfer."""
    try:
        data = request.json
        action = data.get('action')  # 'proceed' or 'cancel'
        handle_overwrites = data.get('handle_overwrites', False)
        
        with state_lock:
            if current_state['status'] != 'confirming':
                return jsonify({'error': 'No transfer pending confirmation'}), 400
            
            current_state['pending_confirmation'] = {
                'action': action,
                'handle_overwrites': handle_overwrites,
                'timestamp': time.time()
            }
        
        # Emit to all connected clients
        socketio.emit('confirmation_received', {
            'action': action,
            'handle_overwrites': handle_overwrites
        })
        
        return jsonify({'success': True})
    
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/network_test')
def test_network():
    """Test network connectivity to NAS."""
    try:
        import subprocess
        
        # Test NAS connectivity
        nas_result = subprocess.run(['ping', '-c', '1', '-W', '5', 'synology.local'], 
                                  capture_output=True)
        nas_available = nas_result.returncode == 0
        
        # Test VPN status
        vpn_result = subprocess.run(['ip', 'route'], capture_output=True, text=True)
        vpn_active = 'tun0' in vpn_result.stdout if vpn_result.returncode == 0 else False
        
        return jsonify({
            'nas_available': nas_available,
            'vpn_active': vpn_active,
            'timestamp': datetime.now().isoformat()
        })
    
    except Exception as e:
        return jsonify({
            'error': str(e),
            'nas_available': False,
            'vpn_active': False
        })

@socketio.on('connect')
def handle_connect():
    """Handle client connection."""
    logging.info('Client connected')
    emit('status_update', current_state)

@socketio.on('disconnect')
def handle_disconnect():
    """Handle client disconnection."""
    logging.info('Client disconnected')

# State update functions called by the main application

def update_status(status, **kwargs):
    """Update system status and broadcast to clients."""
    with state_lock:
        current_state['status'] = status
        current_state.update(kwargs)
    
    socketio.emit('status_update', current_state)

def update_device_info(device_info):
    """Update detected device information."""
    with state_lock:
        current_state['device_info'] = device_info
    
    socketio.emit('device_detected', device_info)

def update_transfer_progress(progress):
    """Update transfer progress."""
    with state_lock:
        current_state['transfer_progress'] = progress
    
    socketio.emit('transfer_progress', progress)

def request_confirmation(device_info, conflicts=None, duplicates=None):
    """Request user confirmation for transfer."""
    confirmation_data = {
        'device_info': device_info,
        'conflicts': conflicts or [],
        'duplicates': duplicates or [],
        'timestamp': time.time()
    }
    
    with state_lock:
        current_state['status'] = 'confirming'
        current_state['pending_confirmation'] = None
    
    socketio.emit('confirmation_required', confirmation_data)
    return confirmation_data

def wait_for_confirmation(timeout_seconds=300):
    """Wait for user confirmation with timeout."""
    start_time = time.time()
    
    while time.time() - start_time < timeout_seconds:
        with state_lock:
            if current_state['pending_confirmation']:
                confirmation = current_state['pending_confirmation']
                current_state['pending_confirmation'] = None
                return confirmation
        
        time.sleep(1)
    
    # Timeout - return default action
    return {'action': 'cancel', 'handle_overwrites': False, 'timeout': True}

if __name__ == '__main__':
    # Initialize settings
    current_state['settings'] = load_settings()
    
    # Start the web server
    socketio.run(app, host='0.0.0.0', port=8080, debug=False)