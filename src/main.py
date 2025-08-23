#!/usr/bin/env python3
"""
Pi SD Offloader - Main application entry point.
Coordinates SD card detection, camera identification, and file transfer.
"""

import os
import sys
import time
import logging
import threading
from datetime import datetime
from pathlib import Path

# Add src directory to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__)))

from core.camera_detector import CameraDetector
from core.transfer_manager import TransferManager, DuplicateManager
from web.app import socketio, app, update_status, update_device_info, update_transfer_progress, request_confirmation, wait_for_confirmation

class SDCardOffloader:
    """Main application coordinator."""
    
    def __init__(self, config_path: str = 'camera_config.yaml'):
        self.logger = self._setup_logging()
        self.config_path = config_path
        
        # Initialize components
        self.camera_detector = CameraDetector(config_path)
        
        # Get settings from camera detector
        config = self.camera_detector.settings
        self.transfer_manager = TransferManager(config.get('transfer_settings', {}))
        self.duplicate_manager = DuplicateManager(config.get('duplicate_handling', {}))
        
        self.logger.info("Pi SD Offloader initialized")
    
    def _setup_logging(self):
        """Setup logging configuration."""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('/var/log/pi-sd-offloader.log'),
                logging.StreamHandler()
            ]
        )
        return logging.getLogger(__name__)
    
    def process_sd_card(self, sd_card_path: str) -> bool:
        """
        Process a detected SD card through the complete workflow.
        Returns True if successful, False otherwise.
        """
        try:
            self.logger.info(f"Processing SD card: {sd_card_path}")
            update_status('detecting')
            
            # Step 1: Detect camera type
            detection_result = self.camera_detector.detect_camera(sd_card_path)
            if not detection_result:
                self.logger.error("Failed to detect camera type")
                update_status('error', error_message="Unknown camera type or unsupported SD card format")
                return False
            
            self.logger.info(f"Detected camera: {detection_result.camera_name}")
            update_device_info(detection_result.__dict__)
            
            # Step 2: Prepare file list
            file_list = self.camera_detector.prepare_file_list(detection_result, sd_card_path)
            if not file_list:
                self.logger.warning("No files found on SD card")
                update_status('error', error_message="No photos or videos found on SD card")
                return False
            
            self.logger.info(f"Found {len(file_list)} files to transfer")
            
            # Step 3: Check for duplicates and conflicts
            source_files = [source for source, _ in file_list]
            duplicates = self.duplicate_manager.check_duplicates(
                source_files, 
                detection_result.camera_id,
                datetime.now().strftime('%Y%m%d')
            )
            
            conflicts = self.duplicate_manager.check_existing_files(
                file_list,
                detection_result.camera_id,
                datetime.now().strftime('%Y%m%d')
            )
            
            # Step 4: Request user confirmation
            if self.camera_detector.settings.get('user_interaction', {}).get('require_confirmation', True):
                self.logger.info("Requesting user confirmation")
                request_confirmation(
                    detection_result.__dict__,
                    conflicts=conflicts,
                    duplicates=duplicates
                )
                
                timeout = self.camera_detector.settings.get('user_interaction', {}).get('timeout_seconds', 300)
                confirmation = wait_for_confirmation(timeout)
                
                if confirmation.get('action') != 'proceed':
                    self.logger.info("Transfer cancelled by user or timeout")
                    update_status('idle')
                    return False
                
                self.logger.info("User confirmed transfer")
            
            # Step 5: Transfer files
            update_status('transferring')
            
            import_date = datetime.now().strftime(
                self.camera_detector.settings.get('date_format', '%Y%m%d')
            )
            
            # Start progress monitoring in background
            progress_thread = threading.Thread(
                target=self._monitor_transfer_progress,
                args=(self.transfer_manager,),
                daemon=True
            )
            progress_thread.start()
            
            # Execute transfer
            stats = self.transfer_manager.transfer_files(
                file_list,
                detection_result.camera_id,
                import_date
            )
            
            # Step 6: Clean up SD card if configured
            if (stats.successful_transfers > 0 and 
                stats.failed_transfers == 0 and
                self.camera_detector.settings.get('transfer_settings', {}).get('delete_after_transfer', False)):
                
                self.logger.info("Cleaning up SD card")
                self._cleanup_sd_card(source_files)
            
            # Step 7: Report results
            if stats.failed_transfers == 0:
                self.logger.info(f"Transfer completed successfully: {stats.successful_transfers} files")
                update_status('complete')
                return True
            else:
                self.logger.error(f"Transfer completed with errors: {stats.failed_transfers} failed")
                update_status('error', error_message=f"{stats.failed_transfers} files failed to transfer")
                return False
        
        except Exception as e:
            self.logger.error(f"Error processing SD card: {e}")
            update_status('error', error_message=str(e))
            return False
    
    def _monitor_transfer_progress(self, transfer_manager):
        """Monitor transfer progress and update web interface."""
        while True:
            progress = transfer_manager.get_progress()
            update_transfer_progress(progress)
            
            # Stop monitoring when transfer is complete
            total = progress['total_files']
            completed = progress['completed_files']
            
            if total > 0 and completed >= total:
                break
            
            time.sleep(1)
    
    def _cleanup_sd_card(self, file_list: list):
        """Safely delete files from SD card after successful transfer."""
        deleted_count = 0
        error_count = 0
        
        for file_path in file_list:
            try:
                if os.path.exists(file_path):
                    os.remove(file_path)
                    deleted_count += 1
                    self.logger.debug(f"Deleted: {file_path}")
            except Exception as e:
                error_count += 1
                self.logger.error(f"Failed to delete {file_path}: {e}")
        
        self.logger.info(f"SD card cleanup: {deleted_count} files deleted, {error_count} errors")
    
    def run_web_interface(self):
        """Start the web interface in a separate thread."""
        def start_web_server():
            port = self.camera_detector.settings.get('user_interaction', {}).get('web_port', 8080)
            self.logger.info(f"Starting web interface on port {port}")
            socketio.run(app, host='0.0.0.0', port=port, debug=False)
        
        web_thread = threading.Thread(target=start_web_server, daemon=True)
        web_thread.start()
        return web_thread

def handle_sd_card_event(device_name: str):
    """
    Handle SD card insertion event.
    This function is called by the udev rule or systemd service.
    """
    # Wait for device to be fully ready
    time.sleep(3)
    
    # Find mount point
    mount_point = None
    possible_mounts = [
        f"/media/pi/{device_name}",
        f"/media/{device_name}",
        f"/mnt/{device_name}",
        f"/media/sdcard/{device_name}"
    ]
    
    for mount in possible_mounts:
        if os.path.exists(mount) and os.path.ismount(mount):
            mount_point = mount
            break
    
    if not mount_point:
        logging.error(f"Could not find mount point for device {device_name}")
        return
    
    # Process the SD card
    config_path = os.path.join(os.path.dirname(__file__), '..', 'camera_config.yaml')
    offloader = SDCardOffloader(config_path)
    
    success = offloader.process_sd_card(mount_point)
    
    if success:
        logging.info(f"Successfully processed SD card: {device_name}")
    else:
        logging.error(f"Failed to process SD card: {device_name}")

def main():
    """Main entry point for the application."""
    if len(sys.argv) > 1:
        # Called with device name (from udev/systemd)
        device_name = sys.argv[1]
        handle_sd_card_event(device_name)
    else:
        # Interactive mode - start web interface and wait
        config_path = os.path.join(os.path.dirname(__file__), '..', 'camera_config.yaml')
        offloader = SDCardOffloader(config_path)
        
        # Start web interface
        web_thread = offloader.run_web_interface()
        
        print("Pi SD Offloader started successfully!")
        print(f"Web interface available at: http://localhost:8080")
        print("Insert an SD card to begin automatic processing.")
        print("Press Ctrl+C to stop.")
        
        try:
            # Keep main thread alive
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            print("\nShutting down Pi SD Offloader...")
            sys.exit(0)

if __name__ == "__main__":
    main()