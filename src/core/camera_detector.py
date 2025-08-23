#!/usr/bin/env python3
"""
Camera detection system using multiple identification methods.
"""

import os
import subprocess
import yaml
import logging
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass

@dataclass
class CameraDetectionResult:
    camera_id: str
    camera_name: str
    confidence_score: int
    detection_methods: List[str]
    file_sources: Dict[str, List[str]]

class CameraDetector:
    """Main camera detection class using configurable rules."""
    
    def __init__(self, config_path: str):
        self.logger = logging.getLogger(__name__)
        self.cameras = {}
        self.settings = {}
        self.load_config(config_path)
    
    def load_config(self, config_path: str):
        """Load camera configuration from YAML file."""
        try:
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)
            
            self.cameras = config.get('cameras', {})
            self.settings = config.get('settings', {})
            self.logger.info(f"Loaded configuration for {len(self.cameras)} camera types")
        
        except Exception as e:
            self.logger.error(f"Failed to load camera config: {e}")
            raise
    
    def detect_camera(self, sd_card_path: str) -> Optional[CameraDetectionResult]:
        """
        Detect camera type using multiple methods and return best match.
        """
        if not os.path.exists(sd_card_path):
            self.logger.error(f"SD card path does not exist: {sd_card_path}")
            return None
        
        detection_results = []
        
        # Test each configured camera
        for camera_id, camera_config in self.cameras.items():
            # Skip MTP devices for SD card detection
            if camera_config.get('connection_type') == 'mtp':
                continue
            
            result = self._test_camera_match(sd_card_path, camera_id, camera_config)
            if result.confidence_score > 0:
                detection_results.append(result)
        
        if not detection_results:
            self.logger.warning(f"No camera detected for {sd_card_path}")
            return None
        
        # Return the result with highest confidence
        best_result = max(detection_results, key=lambda x: x.confidence_score)
        self.logger.info(f"Detected camera: {best_result.camera_name} "
                        f"(confidence: {best_result.confidence_score})")
        
        return best_result
    
    def _test_camera_match(self, sd_card_path: str, camera_id: str, 
                          camera_config: Dict) -> CameraDetectionResult:
        """Test if SD card matches a specific camera configuration."""
        
        confidence_score = 0
        detection_methods = []
        
        # Test folder structure
        structure_score = self._test_folder_structure(sd_card_path, 
                                                    camera_config.get('detection_rules', {}).get('folder_structure', []))
        if structure_score > 0:
            confidence_score += structure_score
            detection_methods.append('folder_structure')
        
        # Test file patterns
        pattern_score = self._test_file_patterns(sd_card_path,
                                               camera_config.get('detection_rules', {}).get('file_patterns', []))
        if pattern_score > 0:
            confidence_score += pattern_score
            detection_methods.append('file_patterns')
        
        # Test EXIF data if files exist
        exif_score = self._test_exif_data(sd_card_path,
                                        camera_config.get('detection_rules', {}).get('exif_rules', {}))
        if exif_score > 0:
            confidence_score += exif_score
            detection_methods.append('exif_data')
        
        # Get file sources if camera detected
        file_sources = {}
        if confidence_score > 0:
            file_sources = self._get_file_sources(sd_card_path, camera_config)
        
        return CameraDetectionResult(
            camera_id=camera_id,
            camera_name=camera_config.get('name', camera_id),
            confidence_score=confidence_score,
            detection_methods=detection_methods,
            file_sources=file_sources
        )
    
    def _test_folder_structure(self, sd_card_path: str, folder_rules: List[Dict]) -> int:
        """Test folder structure patterns."""
        score = 0
        
        for rule in folder_rules:
            folder_path = os.path.join(sd_card_path, rule.get('path', ''))
            
            if os.path.exists(folder_path):
                if rule.get('required', False):
                    score += 30  # High score for required folders
                else:
                    score += 10  # Lower score for optional folders
            elif rule.get('required', False):
                # Required folder missing - this camera type doesn't match
                return 0
        
        return score
    
    def _test_file_patterns(self, sd_card_path: str, pattern_rules: List[Dict]) -> int:
        """Test file naming patterns."""
        score = 0
        
        for rule in pattern_rules:
            pattern = rule.get('pattern', '')
            confidence = rule.get('confidence', 50)
            
            # Convert glob pattern to find command
            try:
                cmd = ['find', sd_card_path, '-name', pattern]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                
                if result.returncode == 0 and result.stdout.strip():
                    # Files matching pattern found
                    file_count = len(result.stdout.strip().split('\n'))
                    score += min(confidence, confidence + file_count * 5)  # Bonus for more files
                
            except subprocess.TimeoutExpired:
                self.logger.warning(f"Pattern search timed out for {pattern}")
        
        return score
    
    def _test_exif_data(self, sd_card_path: str, exif_rules: Dict) -> int:
        """Test EXIF data from sample files."""
        if not exif_rules:
            return 0
        
        # Find sample image/video files
        sample_files = self._find_sample_files(sd_card_path)
        if not sample_files:
            return 0
        
        score = 0
        expected_make = exif_rules.get('make', '').lower()
        model_contains = exif_rules.get('model_contains', [])
        confidence = exif_rules.get('confidence', 95)
        
        for sample_file in sample_files[:3]:  # Test up to 3 files
            try:
                cmd = ['exiftool', '-Make', '-Model', '-s', '-s', '-s', sample_file]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                
                if result.returncode == 0:
                    lines = result.stdout.strip().split('\n')
                    if len(lines) >= 2:
                        make = lines[0].lower()
                        model = lines[1].lower()
                        
                        # Check make
                        if expected_make and expected_make in make:
                            score += confidence // 2
                        
                        # Check model contains
                        for model_part in model_contains:
                            if model_part.lower() in model:
                                score += confidence // 2
                                break
            
            except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
                continue
        
        return min(score, confidence)  # Cap at maximum confidence
    
    def _find_sample_files(self, sd_card_path: str) -> List[str]:
        """Find sample files for EXIF testing."""
        extensions = ['.jpg', '.jpeg', '.arw', '.mp4', '.mov', '.lrf']
        sample_files = []
        
        for ext in extensions:
            try:
                cmd = ['find', sd_card_path, '-iname', f'*{ext}', '-type', 'f']
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
                
                if result.returncode == 0 and result.stdout.strip():
                    files = result.stdout.strip().split('\n')
                    sample_files.extend(files[:2])  # Take first 2 files of each type
                
                if len(sample_files) >= 5:  # Limit total sample size
                    break
            
            except subprocess.TimeoutExpired:
                continue
        
        return sample_files
    
    def _get_file_sources(self, sd_card_path: str, camera_config: Dict) -> Dict[str, List[str]]:
        """Get actual files from the camera based on its configuration."""
        file_sources = {}
        
        sources_config = camera_config.get('file_sources', {})
        
        for file_type, source_configs in sources_config.items():
            files = []
            
            for source_config in source_configs:
                source_path = os.path.join(sd_card_path, source_config.get('path', ''))
                extensions = source_config.get('extensions', [])
                recursive = source_config.get('recursive', False)
                
                if os.path.exists(source_path):
                    found_files = self._find_files_in_path(source_path, extensions, recursive)
                    files.extend(found_files)
            
            if files:
                file_sources[file_type] = files
        
        return file_sources
    
    def _find_files_in_path(self, path: str, extensions: List[str], recursive: bool) -> List[str]:
        """Find files with specific extensions in a path."""
        files = []
        
        if not extensions:
            return files
        
        for ext in extensions:
            try:
                if recursive:
                    cmd = ['find', path, '-iname', f'*{ext}', '-type', 'f']
                else:
                    cmd = ['find', path, '-maxdepth', '1', '-iname', f'*{ext}', '-type', 'f']
                
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
                
                if result.returncode == 0 and result.stdout.strip():
                    found_files = result.stdout.strip().split('\n')
                    files.extend(found_files)
            
            except subprocess.TimeoutExpired:
                continue
        
        return sorted(list(set(files)))  # Remove duplicates and sort
    
    def prepare_file_list(self, detection_result: CameraDetectionResult, 
                         sd_card_path: str) -> List[Tuple[str, str]]:
        """
        Prepare file list for transfer with source and relative destination paths.
        Returns list of (source_path, relative_dest_path) tuples.
        """
        file_list = []
        
        for file_type, files in detection_result.file_sources.items():
            for file_path in files:
                # Calculate relative path from SD card root
                try:
                    rel_path = os.path.relpath(file_path, sd_card_path)
                    
                    # Organize by file type if preserve_folder_structure is False
                    if not self.settings.get('preserve_folder_structure', True):
                        filename = os.path.basename(file_path)
                        rel_path = os.path.join(file_type, filename)
                    
                    file_list.append((file_path, rel_path))
                
                except ValueError:
                    # File is not under SD card path, skip
                    self.logger.warning(f"File outside SD card path: {file_path}")
                    continue
        
        return file_list

class USBDeviceDetector:
    """Detector for USB-connected devices like Insta360 Go3."""
    
    def __init__(self, config_path: str):
        self.logger = logging.getLogger(__name__)
        self.cameras = {}
        self.load_config(config_path)
    
    def load_config(self, config_path: str):
        """Load camera configuration."""
        try:
            with open(config_path, 'r') as f:
                config = yaml.safe_load(f)
            self.cameras = {k: v for k, v in config.get('cameras', {}).items() 
                          if v.get('connection_type') == 'mtp'}
        except Exception as e:
            self.logger.error(f"Failed to load USB device config: {e}")
    
    def detect_mtp_devices(self) -> List[CameraDetectionResult]:
        """Detect MTP devices like Insta360 Go3."""
        detected_devices = []
        
        try:
            # Check for MTP devices using lsusb
            result = subprocess.run(['lsusb'], capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0:
                for camera_id, camera_config in self.cameras.items():
                    vendor_id = camera_config.get('detection_rules', {}).get('usb_vendor_id', '')
                    product_id = camera_config.get('detection_rules', {}).get('usb_product_id', '')
                    
                    if vendor_id and product_id:
                        if f"{vendor_id}:{product_id}" in result.stdout:
                            detected_devices.append(CameraDetectionResult(
                                camera_id=camera_id,
                                camera_name=camera_config.get('name', camera_id),
                                confidence_score=95,
                                detection_methods=['usb_detection'],
                                file_sources={}  # Would need MTP tools to populate
                            ))
        
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as e:
            self.logger.error(f"Failed to detect USB devices: {e}")
        
        return detected_devices