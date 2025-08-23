#!/usr/bin/env python3
"""
File transfer manager with checksum validation and network fallback handling.
"""

import os
import shutil
import hashlib
import subprocess
import time
import logging
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass

@dataclass
class TransferResult:
    success: bool
    source_file: str
    dest_file: str
    checksum: str
    error_message: Optional[str] = None
    transfer_time: float = 0.0

@dataclass
class TransferStats:
    total_files: int = 0
    successful_transfers: int = 0
    failed_transfers: int = 0
    total_size: int = 0
    transferred_size: int = 0
    start_time: float = 0.0
    end_time: float = 0.0

class NetworkManager:
    """Handles network connectivity testing and NAS availability."""
    
    def __init__(self, config: dict):
        self.config = config
        self.logger = logging.getLogger(__name__)
    
    def test_nas_connectivity(self) -> bool:
        """Test if NAS is reachable."""
        try:
            cmd = self.config.get('nas_test_command', 'ping -c 1 -W 5 synology.local')
            result = subprocess.run(cmd.split(), 
                                  capture_output=True, 
                                  timeout=self.config.get('nas_timeout_seconds', 10))
            return result.returncode == 0
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
            return False
    
    def check_vpn_status(self) -> bool:
        """Check if VPN connection is active."""
        try:
            cmd = self.config.get('vpn_check_command', 'ip route | grep -q tun0')
            result = subprocess.run(cmd, shell=True, capture_output=True)
            return result.returncode == 0
        except subprocess.CalledProcessError:
            return False
    
    def get_connection_status(self) -> Dict[str, bool]:
        """Get comprehensive network status."""
        return {
            'nas_available': self.test_nas_connectivity(),
            'vpn_active': self.check_vpn_status()
        }

class ChecksumManager:
    """Handles file checksum calculation and verification."""
    
    @staticmethod
    def calculate_checksum(file_path: str, algorithm: str = 'sha256') -> str:
        """Calculate checksum for a file."""
        hash_func = getattr(hashlib, algorithm)()
        
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(8192), b""):
                hash_func.update(chunk)
        
        return hash_func.hexdigest()
    
    @staticmethod
    def verify_transfer(source_file: str, dest_file: str) -> bool:
        """Verify file transfer integrity using checksums."""
        if not os.path.exists(dest_file):
            return False
        
        try:
            source_checksum = ChecksumManager.calculate_checksum(source_file)
            dest_checksum = ChecksumManager.calculate_checksum(dest_file)
            return source_checksum == dest_checksum
        except Exception:
            return False

class TransferManager:
    """Main transfer manager handling file operations with fallback logic."""
    
    def __init__(self, config: dict):
        self.config = config
        self.network_manager = NetworkManager(config.get('network_settings', {}))
        self.logger = logging.getLogger(__name__)
        self.stats = TransferStats()
        
        # Create necessary directories
        self._ensure_directories()
    
    def _ensure_directories(self):
        """Create necessary directories if they don't exist."""
        local_path = self.config.get('local_storage_path', '/tmp/photos')
        nas_path = self.config.get('nas_storage_path', '/mnt/nas/Photos')
        
        os.makedirs(local_path, exist_ok=True)
        os.makedirs(os.path.dirname(nas_path), exist_ok=True)
    
    def _get_transfer_mode(self) -> str:
        """Determine the appropriate transfer mode based on network status."""
        transfer_mode = self.config.get('transfer_mode', 'auto')
        
        if transfer_mode == 'auto':
            network_status = self.network_manager.get_connection_status()
            
            if network_status['nas_available']:
                return 'direct_nas'
            elif self.config.get('fallback_to_local', True):
                return 'local_first'
            else:
                raise Exception("NAS not available and local fallback disabled")
        
        return transfer_mode
    
    def _copy_file_with_verification(self, source: str, destination: str, 
                                   preserve_timestamps: bool = True) -> TransferResult:
        """Copy a single file with checksum verification."""
        start_time = time.time()
        result = TransferResult(
            success=False,
            source_file=source,
            dest_file=destination,
            checksum=""
        )
        
        try:
            # Calculate source checksum before transfer
            source_checksum = ChecksumManager.calculate_checksum(source)
            result.checksum = source_checksum
            
            # Ensure destination directory exists
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            
            # Copy file
            shutil.copy2(source, destination)
            
            # Verify transfer
            if ChecksumManager.verify_transfer(source, destination):
                result.success = True
                
                # Preserve timestamps if requested
                if preserve_timestamps:
                    stat = os.stat(source)
                    os.utime(destination, (stat.st_atime, stat.st_mtime))
                
                self.logger.info(f"Successfully transferred: {source} -> {destination}")
            else:
                result.error_message = "Checksum verification failed"
                self.logger.error(f"Checksum verification failed for {source}")
                
                # Remove corrupted file
                if os.path.exists(destination):
                    os.remove(destination)
        
        except Exception as e:
            result.error_message = str(e)
            self.logger.error(f"Transfer failed for {source}: {e}")
        
        result.transfer_time = time.time() - start_time
        return result
    
    def transfer_files(self, file_list: List[Tuple[str, str]], 
                      device_name: str, import_date: str) -> TransferStats:
        """Transfer a list of files with the configured strategy."""
        self.stats = TransferStats()
        self.stats.start_time = time.time()
        self.stats.total_files = len(file_list)
        
        # Calculate total size
        for source, _ in file_list:
            try:
                self.stats.total_size += os.path.getsize(source)
            except OSError:
                pass
        
        transfer_mode = self._get_transfer_mode()
        self.logger.info(f"Using transfer mode: {transfer_mode}")
        
        if transfer_mode == 'direct_nas':
            self._transfer_direct_to_nas(file_list, device_name, import_date)
        else:  # local_first
            self._transfer_local_first(file_list, device_name, import_date)
        
        self.stats.end_time = time.time()
        return self.stats
    
    def _transfer_direct_to_nas(self, file_list: List[Tuple[str, str]], 
                               device_name: str, import_date: str):
        """Transfer files directly to NAS."""
        nas_base = self.config.get('nas_storage_path', '/mnt/nas/Photos')
        
        for source, relative_dest in file_list:
            nas_dest = os.path.join(nas_base, device_name, import_date, relative_dest)
            
            result = self._copy_file_with_verification(
                source, nas_dest, 
                self.config.get('preserve_timestamps', True)
            )
            
            self._update_stats(result, source)
    
    def _transfer_local_first(self, file_list: List[Tuple[str, str]], 
                             device_name: str, import_date: str):
        """Transfer files to local storage first, then sync to NAS."""
        local_base = self.config.get('local_storage_path', '/tmp/photos')
        
        # First, transfer to local storage
        local_transfers = []
        for source, relative_dest in file_list:
            local_dest = os.path.join(local_base, device_name, import_date, relative_dest)
            
            result = self._copy_file_with_verification(
                source, local_dest,
                self.config.get('preserve_timestamps', True)
            )
            
            self._update_stats(result, source)
            
            if result.success:
                local_transfers.append((local_dest, relative_dest))
        
        # Attempt to sync to NAS if network becomes available
        self._sync_to_nas_async(local_transfers, device_name, import_date)
    
    def _sync_to_nas_async(self, local_files: List[Tuple[str, str]], 
                          device_name: str, import_date: str):
        """Asynchronously sync local files to NAS when network is available."""
        # This could be improved with a background worker/queue system
        if self.network_manager.test_nas_connectivity():
            nas_base = self.config.get('nas_storage_path', '/mnt/nas/Photos')
            
            for local_file, relative_dest in local_files:
                nas_dest = os.path.join(nas_base, device_name, import_date, relative_dest)
                
                try:
                    result = self._copy_file_with_verification(local_file, nas_dest)
                    if result.success:
                        self.logger.info(f"Synced to NAS: {nas_dest}")
                        # Optionally remove local file after successful NAS sync
                        # os.remove(local_file)
                except Exception as e:
                    self.logger.error(f"Failed to sync {local_file} to NAS: {e}")
    
    def _update_stats(self, result: TransferResult, source_file: str):
        """Update transfer statistics."""
        if result.success:
            self.stats.successful_transfers += 1
            try:
                self.stats.transferred_size += os.path.getsize(source_file)
            except OSError:
                pass
        else:
            self.stats.failed_transfers += 1
    
    def get_progress(self) -> Dict:
        """Get current transfer progress."""
        elapsed_time = time.time() - self.stats.start_time if self.stats.start_time > 0 else 0
        
        return {
            'total_files': self.stats.total_files,
            'completed_files': self.stats.successful_transfers + self.stats.failed_transfers,
            'successful_transfers': self.stats.successful_transfers,
            'failed_transfers': self.stats.failed_transfers,
            'total_size': self.stats.total_size,
            'transferred_size': self.stats.transferred_size,
            'elapsed_time': elapsed_time,
            'transfer_rate': self.stats.transferred_size / elapsed_time if elapsed_time > 0 else 0
        }

class DuplicateManager:
    """Manages duplicate detection with per-device-per-day scope."""
    
    def __init__(self, config: dict):
        self.config = config
        self.logger = logging.getLogger(__name__)
    
    def check_duplicates(self, file_list: List[str], device_name: str, 
                        import_date: str) -> Dict[str, List[str]]:
        """
        Check for duplicates within the current device and date scope.
        Returns dict of {checksum: [list_of_files_with_same_checksum]}
        """
        duplicates = {}
        checksums = {}
        
        for file_path in file_list:
            try:
                checksum = ChecksumManager.calculate_checksum(file_path)
                
                if checksum in checksums:
                    # Duplicate found
                    if checksum not in duplicates:
                        duplicates[checksum] = [checksums[checksum]]
                    duplicates[checksum].append(file_path)
                else:
                    checksums[checksum] = file_path
            
            except Exception as e:
                self.logger.error(f"Error calculating checksum for {file_path}: {e}")
        
        return duplicates
    
    def check_existing_files(self, file_list: List[Tuple[str, str]], 
                           device_name: str, import_date: str) -> List[str]:
        """
        Check if files already exist in the destination directory.
        Returns list of files that would cause overwrites.
        """
        conflicts = []
        
        # Check both local and NAS paths
        local_base = self.config.get('local_storage_path', '/tmp/photos')
        nas_base = self.config.get('nas_storage_path', '/mnt/nas/Photos')
        
        for source, relative_dest in file_list:
            local_path = os.path.join(local_base, device_name, import_date, relative_dest)
            nas_path = os.path.join(nas_base, device_name, import_date, relative_dest)
            
            if os.path.exists(local_path) or os.path.exists(nas_path):
                conflicts.append(relative_dest)
        
        return conflicts