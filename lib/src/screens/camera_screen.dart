// lib/src/screens/camera_screen.dart
import 'dart:async';
import 'dart:io';
import 'dart:math'; // Import math for pi
import 'dart:typed_data'; // Import for Uint8List
import 'dart:ui'; // Import for ImageFilter
import 'dart:ui' as ui; // for image capture & flip

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; // Import for compute
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:sensors_plus/sensors_plus.dart'; // Import sensors_plus
import 'package:porcupine_flutter/porcupine_manager.dart'; // Import Porcupine
import 'package:porcupine_flutter/porcupine_error.dart'; // Import Porcupine exceptions
import 'package:rhino_flutter/rhino.dart'; // Import Rhino
import 'package:rhino_flutter/rhino_manager.dart'; // Import RhinoManager
import 'package:rhino_flutter/rhino_error.dart'; // Import Rhino exceptions
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Import flutter_dotenv

import '../utils/logger.dart'; // Import logger
import '../utils/image_utils.dart'; // Import image utils
import '../utils/orientation_service.dart'; // Import orientation service
import 'error_screen.dart'; // Import error screen
import 'gallery_screen.dart'; // Import the new gallery screen
import '../widgets/shutter_button.dart';
import '../widgets/thumbnail_widget.dart';

enum ListeningState {
  idle, // 초기 상태 또는 오류
  waitingForWakeWord, // Porcupine 활성화
  waitingForCommand, // Rhino 활성화
  processingCommand // Rhino 처리 중 (옵션)
}

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras; // Receive cameras list
  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  int _selectedCameraIndex = 0;
  bool _isSwitchingCamera = false; // 전환 중 상태
  bool _isTakingPicture = false;
  bool _isShutterPressed = false; // 촬영 버튼 눌림 상태
  XFile?
      _lastCapturedImage; // Variable to hold the last captured image for thumbnail
  List<String> _savedImagePaths = []; // List to store saved image paths

  // Orientation state
  OrientationService? _orientationService;
  int _deviceOrientationDegrees = 0;

  // 상태 피드백용 변수
  bool _showFlash = false;

  // --- 프리뷰 페이드 효과용 변수 ---
  bool _showPreview = true;

  Duration? _lastShutterDuration; // 마지막 셔터 지속 시간

  // --- Device Rotation ---
  int _deviceRotationDegrees = 0;
  StreamSubscription? _accelSubscription;

  // --- Porcupine Wake Word ---
  PorcupineManager? _porcupineManager;
  String? _porcupineError;

  // --- Rhino Speech-to-Intent ---
  RhinoManager? _rhinoManager;
  String? _rhinoError;
  RhinoInference? _lastInference; // Store last inference result

  // --- Combined Listening State ---
  ListeningState _listeningState = ListeningState.idle;
  String? _errorMessage; // Combined error message

  // --- Picovoice Access Key ---
  // Read from environment variable, provide a fallback if needed
  final String _picovoiceAccessKey =
      dotenv.env['PICOVOICE_ACCESS_KEY'] ?? "YOUR_FALLBACK_KEY";

  List<CameraDescription> get cameras =>
      widget.cameras; // Access cameras via widget

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Check if the access key was loaded correctly
    if (_picovoiceAccessKey == "YOUR_FALLBACK_KEY") {
      logError(
          'Access Key Error', 'PICOVOICE_ACCESS_KEY not found in .env file!');
      // Optionally set an error state here
      setState(() {
        _errorMessage = "Picovoice Access Key not found";
        _listeningState = ListeningState.idle;
      });
      // Prevent further initialization if key is missing
      // return; // Or handle differently
    } else {
      logError('Access Key Info', 'Picovoice Access Key loaded successfully.');
    }

    if (cameras.isNotEmpty) {
      _initializeCamera(0);
    } else {
      _initializeControllerFuture =
          Future.error("No cameras found during init state.");
    }
    // OrientationService 사용
    _orientationService = OrientationService(onChanged: (deg) {
      setState(() {
        _deviceOrientationDegrees = deg;
      });
    });
    _orientationService!.start();

    // Accelerometer subscription for device rotation
    _accelSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      if (event.y.abs() > event.x.abs()) {
        if (event.y < 0) {
          _deviceRotationDegrees = 0; // 세로(정방향)
        } else {
          _deviceRotationDegrees = 180; // 세로(거꾸로)
        }
      } else {
        if (event.x > 0) {
          _deviceRotationDegrees = 90; // 가로(왼쪽이 위)
        } else {
          _deviceRotationDegrees = 270; // 가로(오른쪽이 위)
        }
      }
    });

    // --- Initialize Porcupine ---
    // Only initialize if the key was loaded and no error state set
    if (_listeningState != ListeningState.idle || _errorMessage == null) {
      _initPorcupine();
    }
  }

  // --- Porcupine Initialization ---
  Future<void> _initPorcupine() async {
    // Ensure access key is set
    if (_picovoiceAccessKey == "YOUR_PICOVOICE_ACCESS_KEY") {
      logError('Porcupine Init Error',
          'Please replace "YOUR_PICOVOICE_ACCESS_KEY" with your actual key.');
      setState(() {
        _errorMessage = "Missing Picovoice Access Key";
        _listeningState = ListeningState.idle;
      });
      return;
    }

    // Define asset paths (relative to pubspec.yaml assets section)
    final String keywordAssetPath = "assets/무지야_ko_android_v3_0_0.ppn";
    final String modelAssetPath = "assets/porcupine_params_ko.pv";

    try {
      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        _picovoiceAccessKey,
        [keywordAssetPath], // List of keyword paths
        _wakeWordDetected, // Callback when wake word is detected
        modelPath:
            modelAssetPath, // Optional: specify model path if not default
        errorCallback: _porcupineErrorCallback, // Callback for errors
      );
      await _porcupineManager?.start();
      setState(() {
        _listeningState = ListeningState.waitingForWakeWord;
        _errorMessage = null; // Clear any previous error
      });
      logError(
          'Porcupine Init', 'Porcupine initialized and started successfully.');
    } on PorcupineException catch (e) {
      logError('Porcupine Init Error',
          'Failed to initialize Porcupine: ${e.message}');
      setState(() {
        _errorMessage = "Porcupine Init Failed: ${e.message}";
        _listeningState = ListeningState.idle;
      });
    } catch (e) {
      logError(
          'Porcupine Init Error', 'Unknown error initializing Porcupine: $e');
      setState(() {
        _errorMessage = "Unknown Porcupine Error";
        _listeningState = ListeningState.idle;
      });
    }
  }

  // --- Rhino Initialization ---
  Future<void> _initRhino() async {
    // Ensure access key is valid before proceeding
    if (_picovoiceAccessKey == "YOUR_FALLBACK_KEY" ||
        _picovoiceAccessKey == "YOUR_PICOVOICE_ACCESS_KEY") {
      logError('Rhino Init Error', 'Invalid or missing Picovoice Access Key.');
      setState(() {
        _errorMessage = "Invalid Picovoice Access Key";
        _listeningState = ListeningState.idle;
      });
      _restartPorcupineAfterCommand(); // Attempt to go back to wake word listening
      return;
    }

    // Define asset paths
    final String contextAssetPath = "assets/카메라_ko_android_v3_0_0.rhn";
    final String rhinoModelAssetPath = "assets/rhino_params_ko.pv";
    logError('Rhino Init',
        'Using Context: $contextAssetPath, Model: $rhinoModelAssetPath');

    try {
      logError('Rhino Init', 'Attempting to create RhinoManager...');
      // Ensure manager is null before creating a new one
      if (_rhinoManager != null) {
        logError('Rhino Init Warning',
            'Existing RhinoManager found. Deleting before creating new one.');
        await _stopRhino(); // Clean up existing instance if any
      }

      _rhinoManager = await RhinoManager.create(
        _picovoiceAccessKey,
        contextAssetPath,
        _intentDetected, // Callback when intent is detected
        modelPath: rhinoModelAssetPath,
        processErrorCallback: _rhinoErrorCallback,
      );
      logError('Rhino Init', 'RhinoManager create call completed.');

      // *** Check if manager is not null AFTER creation ***
      if (_rhinoManager != null) {
        logError('Rhino Init',
            'RhinoManager successfully created (instance is not null).');
        logError('Rhino Init', 'Attempting to start Rhino processing...');
        // Start processing audio
        await _rhinoManager!.process(); // Use ! because we checked for null
        logError('Rhino Init', 'Rhino processing started successfully.');
        if (mounted) {
          setState(() {
            _listeningState = ListeningState.waitingForCommand;
            _errorMessage = null; // Clear any previous error
          });
        }
      } else {
        // This case indicates create() returned null or failed silently
        logError('Rhino Init Error',
            'RhinoManager is NULL after creation call completed.');
        throw RhinoInvalidStateException(
            "RhinoManager became null unexpectedly after creation.");
      }
    } on RhinoException catch (e) {
      // Catch specific Rhino exceptions (Activation, IO, InvalidState, etc.)
      logError('Rhino Init Error',
          'RhinoException caught: ${e.runtimeType} - ${e.message}');
      if (mounted) {
        setState(() {
          _errorMessage = "Rhino Init Failed: ${e.message}";
          _listeningState = ListeningState.idle;
        });
      }
      _restartPorcupineAfterCommand();
    } on PlatformException catch (e) {
      // Catch potential errors from native side during create/process
      logError('Rhino Init Error',
          'PlatformException caught: ${e.code} - ${e.message}');
      if (mounted) {
        setState(() {
          _errorMessage = "Rhino Platform Error: ${e.message}";
          _listeningState = ListeningState.idle;
        });
      }
      _restartPorcupineAfterCommand();
    } catch (e, stackTrace) {
      // Catch any other unexpected errors
      logError(
          'Rhino Init Error', 'Unknown error during Rhino initialization: $e');
      logError('Rhino Init Error', 'Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = "Unknown Rhino Error";
          _listeningState = ListeningState.idle;
        });
      }
      _restartPorcupineAfterCommand();
    }
  }

  // --- Porcupine Callbacks ---
  void _wakeWordDetected(int keywordIndex) {
    logError('Porcupine Wake Word', 'Wake word detected! Index: $keywordIndex');
    // Stop Porcupine and start Rhino
    _stopPorcupine().then((_) {
      _initRhino(); // Initialize and wait for Rhino command
    });
  }

  void _porcupineErrorCallback(PorcupineException error) {
    logError('Porcupine Runtime Error', 'Error: ${error.message}');
    setState(() {
      _errorMessage = "Porcupine Runtime Error: ${error.message}";
      _listeningState = ListeningState.idle;
    });
  }

  // --- Rhino Callbacks ---
  void _intentDetected(RhinoInference inference) {
    logError('Rhino Intent',
        'Inference received: understood=${inference.isUnderstood}, intent=${inference.intent}, slots=${inference.slots}');
    setState(() {
      _lastInference = inference; // Store for potential display or logging
    });

    if (inference.isUnderstood == true) {
      // --- Handle Intents ---
      switch (inference.intent) {
        case 'takephoto':
          logError('Rhino Intent', 'Executing: takephoto');
          if (!_isTakingPicture) {
            _takePicture();
          } else {
            logError(
                'Rhino Intent', 'Already taking picture, ignoring command.');
          }
          break;
        case 'evaluateScene':
          logError(
              'Rhino Intent', 'Executing: evaluateScene (Not implemented yet)');
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Scene evaluation not implemented yet.')));
          break;
        case 'openGallery':
          logError('Rhino Intent', 'Executing: openGallery');
          if (_savedImagePaths.isNotEmpty) {
            logError('Rhino Intent', 'Navigating to GalleryScreen');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GalleryScreen(imagePaths: _savedImagePaths),
              ),
            );
          } else {
            logError('Rhino Intent', 'No saved images to show in gallery.');
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('갤러리에 사진이 없습니다.')));
          }
          break;
        default:
          logError('Rhino Intent', 'Unknown intent: ${inference.intent}');
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('알 수 없는 명령입니다: ${inference.intent}')));
      }
    } else {
      logError('Rhino Intent', 'Command not understood.');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('명령을 이해하지 못했습니다.')));
    }

    // --- Cleanup Rhino and Restart Porcupine ---
    _restartPorcupineAfterCommand();
  }

  void _rhinoErrorCallback(RhinoException error) {
    logError('Rhino Runtime Error', 'Error: ${error.message}');
    setState(() {
      _errorMessage = "Rhino Runtime Error: ${error.message}";
      _listeningState = ListeningState.idle;
    });
    // Attempt to restart Porcupine after Rhino error
    _restartPorcupineAfterCommand();
  }

  // --- Helper methods for stopping/starting managers ---
  Future<void> _stopPorcupine() async {
    if (_porcupineManager != null) {
      try {
        await _porcupineManager?.stop();
        logError('Porcupine Control', 'Porcupine stopped.');
      } catch (e) {
        logError('Porcupine Control Error', 'Error stopping Porcupine: $e');
      }
    }
  }

  Future<void> _stopRhino() async {
    if (_rhinoManager != null) {
      try {
        await _rhinoManager?.delete();
        _rhinoManager = null; // Ensure it's null after deletion
        logError('Rhino Control', 'Rhino deleted.');
      } catch (e) {
        logError('Rhino Control Error', 'Error deleting Rhino: $e');
        setState(() {
          _rhinoManager = null;
        });
      }
    }
  }

  Future<void> _restartPorcupineAfterCommand() async {
    await _stopRhino(); // Ensure Rhino is stopped and deleted first
    if (_porcupineManager != null &&
        _listeningState != ListeningState.waitingForWakeWord) {
      try {
        await _porcupineManager?.start();
        if (mounted) {
          setState(() {
            _listeningState = ListeningState.waitingForWakeWord;
            _errorMessage = null; // Clear Rhino errors
          });
        }
        logError(
            'Porcupine Control', 'Porcupine restarted after command/error.');
      } catch (e) {
        logError('Porcupine Control Error', 'Error restarting Porcupine: $e');
        if (mounted) {
          setState(() {
            _errorMessage = "Failed to restart Porcupine";
            _listeningState = ListeningState.idle;
          });
        }
      }
    } else if (_porcupineManager == null) {
      logError(
          'Porcupine Control', 'Porcupine manager was null, re-initializing.');
      _initPorcupine(); // Re-initialize if it was somehow deleted
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose().catchError((e) {
      logError('Dispose Error', 'Error disposing controller: $e');
    });
    _orientationService?.stop();
    _accelSubscription?.cancel();

    // Stop and delete both managers
    _stopPorcupine().then((_) {
      _porcupineManager?.delete();
      logError('Porcupine Dispose', 'Porcupine deleted.');
    }).catchError((e) {
      logError('Porcupine Dispose Error', 'Error deleting Porcupine: $e');
    });

    _stopRhino(); // Rhino stop/delete

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    logError('Lifecycle Info', 'App state changed to: $state');

    if (state != AppLifecycleState.resumed &&
        (cameraController == null || !cameraController.value.isInitialized)) {
      logError('Lifecycle Info',
          'State is $state, but controller not ready. Doing nothing.');
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        logError('Lifecycle Info', 'App resumed.');
        if (cameraController == null || !cameraController.value.isInitialized) {
          logError('Lifecycle Info',
              'Controller not ready, initializing camera $_selectedCameraIndex');
          _initializeCamera(_selectedCameraIndex);
        } else {
          logError('Lifecycle Info', 'Controller already initialized.');
        }
        // Restart Porcupine if idle and no error
        if (_listeningState == ListeningState.idle && _errorMessage == null) {
          logError('Picovoice Lifecycle', 'Resuming - Restarting Porcupine.');
          _restartPorcupineAfterCommand();
        } else if (_listeningState == ListeningState.waitingForCommand) {
          logError('Picovoice Lifecycle',
              'Resuming - Was waiting for command, restarting Porcupine.');
          _restartPorcupineAfterCommand();
        }
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        logError('Lifecycle Info',
            'App inactive/paused/detached. Disposing controller.');
        if (cameraController != null && cameraController.value.isInitialized) {
          cameraController.dispose().then((_) {
            if (mounted) {
              setState(() {
                _controller = null;
                _initializeControllerFuture = null;
              });
              logError('Lifecycle Info', 'Controller disposed successfully.');
            }
          }).catchError((e) {
            logError(
                'Dispose Error', 'Error disposing controller on $state: $e');
            if (mounted) {
              setState(() {
                _controller = null;
                _initializeControllerFuture = null;
              });
            }
          });
        } else {
          logError('Lifecycle Info',
              'Controller was already null or not initialized during $state.');
          if (_initializeControllerFuture != null && mounted) {
            setState(() {
              _initializeControllerFuture = null;
            });
          }
        }
        // Stop whichever manager is active
        if (_listeningState == ListeningState.waitingForWakeWord) {
          logError('Picovoice Lifecycle', 'Pausing - Stopping Porcupine.');
          _stopPorcupine();
        } else if (_listeningState == ListeningState.waitingForCommand) {
          logError('Picovoice Lifecycle', 'Pausing - Stopping Rhino.');
          _stopRhino();
          setState(() => _listeningState = ListeningState.idle);
        }
        break;
      case AppLifecycleState.hidden:
        logError('Lifecycle Info', 'App hidden.');
        break;
    }
  }

  Future<void> _initializeCamera(int cameraIndex) async {
    if (_controller != null &&
        _selectedCameraIndex == cameraIndex &&
        _controller!.value.isInitialized) {
      logError(
          'Initialization Info', 'Camera $cameraIndex already initialized.');
      return;
    }
    // 전환 중 표시
    setState(() {
      _isSwitchingCamera = true;
    });
    if (_controller != null) {
      await _controller!.dispose().catchError((e) {
        logError('Dispose Error', 'Error disposing previous controller: $e');
      });
      if (mounted) {
        setState(() {
          _controller = null;
        });
      }
    }
    if (cameraIndex < 0 || cameraIndex >= cameras.length) {
      logError('Initialization Error', 'Invalid camera index: $cameraIndex');
      if (mounted) {
        setState(() {
          _initializeControllerFuture = Future.error('Invalid camera index');
          _isSwitchingCamera = false;
        });
      }
      return;
    }
    _selectedCameraIndex = cameraIndex;
    final CameraDescription cameraDescription = cameras[cameraIndex];
    _controller = CameraController(
      cameraDescription,
      // 해상도를 high로 변경
      ResolutionPreset.ultraHigh,
      enableAudio: false,
      // iOS 관련 코드 제거, Android 기본값 사용
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    _initializeControllerFuture = _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _isSwitchingCamera = false;
      });
      logError('Initialization Info',
          'Camera ${cameraDescription.name} initialized successfully.');
    }).catchError((error) {
      String errorMessage = 'Failed to initialize camera.';
      if (error is CameraException) {
        logError('Camera Error',
            'Code: ${error.code}\nDescription: ${error.description}');
        switch (error.code) {
          case 'CameraAccessDenied':
          case 'CameraAccessDeniedWithoutPrompt':
            errorMessage =
                'Camera access denied. Please grant permission in settings.';
            break;
          case 'CameraAccessRestricted':
            errorMessage =
                'Camera access is restricted (e.g., parental controls).';
            break;
          case 'AudioAccessDenied':
            errorMessage =
                'Audio access denied. This might affect camera functionality.';
            break;
          default:
            errorMessage = 'Camera Error: ${error.description} (${error.code})';
        }
      } else {
        logError('Initialization Error', 'Unknown error: $error');
        errorMessage =
            'An unknown error occurred during camera initialization.';
      }

      if (mounted) {
        setState(() {
          _initializeControllerFuture = Future.error(error);
          _isSwitchingCamera = false;
        });
      }
      _controller?.dispose().catchError((e) {
        logError('Dispose Error', 'Error disposing failed controller: $e');
      });
      if (mounted) {
        setState(() {
          _controller = null;
        });
      }
    });

    if (mounted) {
      setState(() {});
    }
  }

  void _switchCamera() async {
    if (cameras.length < 2 ||
        _controller == null ||
        !_controller!.value.isInitialized ||
        _isTakingPicture ||
        _isSwitchingCamera) {
      // Prevent switching if already switching
      logError(
          'Switch Camera Info', 'Cannot switch camera - conditions not met.');
      return;
    }
    setState(() {
      _showPreview = false;
      _isSwitchingCamera = true;
    }); // 프리뷰 페이드 아웃 & 로딩 시작

    await Future.delayed(const Duration(milliseconds: 150)); // 더 빠른 전환
    int nextCameraIndex = (_selectedCameraIndex + 1) % cameras.length;
    await _initializeCamera(nextCameraIndex);
    await Future.delayed(const Duration(milliseconds: 80)); // 새 프리뷰 준비 시간
    setState(() {
      _showPreview = true;
    }); // 프리뷰 페이드 인 & 로딩 종료
  }

  Future<void> _takePicture() async {
    if (_isTakingPicture) return;
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized)
      return;
    try {
      await _initializeControllerFuture;
    } catch (e) {
      return;
    }
    setState(() {
      _isTakingPicture = true;
      _lastShutterDuration = null; // 촬영 시작 시 인디케이터 초기화
    });
    // Flash-Blink 효과
    _triggerFlashBlink();
    final DateTime start = DateTime.now();
    try {
      final XFile imageFile = await cameraController.takePicture();
      String fileToSave = imageFile.path;
      final bool isFrontCamera = cameraController.description.lensDirection ==
          CameraLensDirection.front;
      int rotate = 0;
      if (_deviceOrientationDegrees == 90)
        rotate = 90;
      else if (_deviceOrientationDegrees == 270) rotate = -90;
      if (isFrontCamera || rotate != 0) {
        final bytes = await File(imageFile.path).readAsBytes();
        final fixedBytes = await rotateAndFlipImage(
          bytes,
          flip: isFrontCamera,
          rotateDegrees: rotate,
        );
        final fixedPath = imageFile.path.replaceFirst('.jpg', '_fixed.jpg');
        await File(fixedPath).writeAsBytes(fixedBytes);
        fileToSave = fixedPath;
      }
      final result = await ImageGallerySaverPlus.saveFile(fileToSave);
      if (mounted) {
        bool success = result['isSuccess'] ?? false;
        if (success) {
          setState(() {
            _lastCapturedImage = XFile(fileToSave);
            _savedImagePaths.add(fileToSave);
          });
        }
      }
    } finally {
      if (mounted) {
        final Duration elapsed = DateTime.now().difference(start);
        setState(() {
          _isTakingPicture = false;
          _lastShutterDuration = elapsed; // 실제 저장 시간 기록
        });
      }
    }
  }

  void _triggerFlashBlink() async {
    setState(() {
      _showFlash = true;
    });
    await Future.delayed(const Duration(milliseconds: 60));
    setState(() {
      _showFlash = false;
    });
  }

  // --- Modified Indicator to show Porcupine/Rhino status ---
  Widget _buildWakeWordIndicator() {
    String text;
    Color color;
    IconData icon;

    if (_errorMessage != null) {
      text = "Error";
      color = Colors.red;
      icon = Icons.error_outline;
    } else {
      switch (_listeningState) {
        case ListeningState.waitingForWakeWord:
          text = "무지야?"; // Waiting for "무지야"
          color = Colors.green;
          icon = Icons.mic_none; // Outline mic
          break;
        case ListeningState.waitingForCommand:
          text = "명령하세요..."; // Waiting for command after "무지야"
          color = Colors.blue;
          icon = Icons.mic; // Filled mic
          break;
        case ListeningState.processingCommand: // Optional state
          text = "처리중...";
          color = Colors.orange;
          icon = Icons.hourglass_empty;
          break;
        case ListeningState.idle:
        default:
          text = "초기화중...";
          color = Colors.grey;
          icon = Icons.hourglass_empty;
          break;
      }
    }

    return Positioned(
      top: 100, // Adjust position as needed
      left: 20,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: Offset(0, 2),
            )
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // --- Camera Preview & 상단 그라데이션 오버레이 ---
            FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                final CameraController? cameraController = _controller;
                final bool isCameraReady =
                    snapshot.connectionState == ConnectionState.done &&
                        cameraController != null &&
                        cameraController.value.isInitialized;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedOpacity(
                      opacity: _showPreview ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: _buildCameraPreview(),
                    ),
                    if (!isCameraReady && snapshot.hasError)
                      Center(
                          child:
                              ErrorScreen(message: snapshot.error.toString())),
                    if (!isCameraReady && !snapshot.hasError && _showPreview)
                      const Center(child: CircularProgressIndicator()),
                    // 상단 그라데이션 오버레이 (더 약하게)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Container(
                          height: 120,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color.fromARGB(120, 0, 0, 0), // 더 약한 블랙
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            // --- Flash-Blink 효과 ---
            if (_showFlash)
              AnimatedOpacity(
                opacity: _showFlash ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 60),
                child: Container(color: Colors.white),
              ),
            // --- 하단 컨트롤 바 ---
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildControlBar(),
            ),
            // --- Wake Word / Command Indicator ---
            _buildWakeWordIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final CameraController? cameraController = _controller;
    // CameraPreview를 절대 조건문 밖에서 생성하지 않음
    if (cameraController == null) return Container(color: Colors.black);
    bool safe = false;
    try {
      safe = cameraController.value.isInitialized &&
          !cameraController.value.isRecordingVideo;
    } catch (_) {
      return Container(color: Colors.black);
    }
    if (!safe) return Container(color: Colors.black);
    final mediaSize = MediaQuery.of(context).size;
    var scale = mediaSize.aspectRatio * cameraController.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    final bool isFrontCamera =
        cameraController.description.lensDirection == CameraLensDirection.front;
    return Center(
      child: Transform.scale(
        scale: scale,
        child: isFrontCamera
            ? Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(pi),
                child: CameraPreview(cameraController),
              )
            : CameraPreview(cameraController),
      ),
    );
  }

  Widget _buildControlBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center, // 높이 기준 중앙 정렬
          children: <Widget>[
            AnimatedScale(
              scale: !_isTakingPicture ? 1.0 : 0.92,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              child: ThumbnailWidget(
                imagePath: _lastCapturedImage?.path,
                onTap: () {
                  if (_savedImagePaths.isNotEmpty) {
                    logError('Thumbnail Tap', 'Navigating to GalleryScreen');
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            GalleryScreen(imagePaths: _savedImagePaths),
                      ),
                    );
                  } else {
                    logError('Thumbnail Tap', 'No saved images to show.');
                  }
                },
              ),
            ),
            Expanded(child: SizedBox()),
            AnimatedScale(
              scale: (!_isTakingPicture && !_isShutterPressed) ? 1.0 : 0.88,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: ShutterButton(
                isTakingPicture: _isTakingPicture,
                isShutterPressed: _isShutterPressed,
                onTap: _takePicture,
                onTapDown: () => setState(() => _isShutterPressed = true),
                onTapUp: () => setState(() => _isShutterPressed = false),
                onTapCancel: () => setState(() => _isShutterPressed = false),
                indicator: _isTakingPicture
                    ? _ArcOnceIndicator(
                        duration: const Duration(milliseconds: 700),
                      )
                    : null,
              ),
            ),
            Expanded(child: SizedBox()),
            AnimatedRotation(
              turns: _isTakingPicture ? 0.1 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: SizedBox(width: 60, child: _buildSwitchCameraButton()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchCameraButton() {
    final bool canSwitch = cameras.length > 1;
    return AnimatedScale(
      scale: _isSwitchingCamera ? 0.82 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      child: IconButton(
        icon: const Icon(Icons.cameraswitch_outlined),
        iconSize: 32,
        color: (_controller != null &&
                _controller!.value.isInitialized &&
                canSwitch &&
                !_isTakingPicture)
            ? Colors.white
            : Colors.grey,
        onPressed: (_controller != null &&
                _controller!.value.isInitialized &&
                canSwitch &&
                !_isTakingPicture &&
                !_isSwitchingCamera)
            ? _switchCamera
            : null,
      ),
    );
  }
}

class _SmoothIndicator extends StatelessWidget {
  final double size;
  final Color color;
  final double sweep;
  final Duration duration;
  const _SmoothIndicator({
    this.size = 52, // 더 크게 버튼 바깥쪽에 위치
    this.color = Colors.white,
    this.sweep = 0.18, // 더 짧은 arc (약 65도)
    this.duration = const Duration(milliseconds: 350), // 더 빠르게
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.linear,
      builder: (context, value, child) {
        return Transform.rotate(
          angle: value * 2 * pi,
          child: CustomPaint(
            size: Size.square(size),
            painter: _ArcIndicatorPainter(
              color: color,
              sweep: sweep,
            ),
          ),
        );
      },
      onEnd: () {},
    );
  }
}

class _ArcIndicatorPainter extends CustomPainter {
  final Color color;
  final double sweep;
  _ArcIndicatorPainter({required this.color, required this.sweep});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final rect = Offset(4, 4) & Size(size.width - 8, size.height - 8);
    canvas.drawArc(rect, -pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ArcOnceIndicator extends StatelessWidget {
  final Duration duration;
  final VoidCallback? onEnd;
  const _ArcOnceIndicator({required this.duration, this.onEnd, super.key});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return CustomPaint(
          painter: _ArcIndicatorPainter(
            color: Colors.yellowAccent.withOpacity(0.7),
            sweep: value * 2 * pi,
          ),
        );
      },
      onEnd: onEnd,
    );
  }
}
