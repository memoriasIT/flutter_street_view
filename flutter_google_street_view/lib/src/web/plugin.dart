part of 'package:flutter_google_street_view/flutter_google_street_view_web.dart';

class FlutterGoogleStreetViewPlugin {
  static final bool _debug = false;

  static Registrar? registrar;

  static void registerWith(Registrar registrar) {
    clear();
    FlutterGoogleStreetViewPlugin.registrar = registrar;
  }

  static clear() {
    resetStreetVIewId();
    _lockMap.clear();
    _plugins.clear();
    _divs.clear();
  }

  static int _streetViewId = -1;

  static void resetStreetVIewId() => _streetViewId = -1;

  static final Map<int, bool> _lockMap = {};
  static final Map<int, FlutterGoogleStreetViewPlugin> _plugins = {};
  static final Map<int, HTMLElement> _divs = {};

  String _getViewType(int viewId) => "my_street_view_$viewId";

  // The Flutter widget that contains the rendered StreetView.
  HtmlElementView? _widget;
  late HTMLElement _div;
  late int _viewId;

  /// The view id of street view.
  int get viewId => _viewId;

  /// The Flutter widget that will contain the rendered Map. Used for caching.
  Widget get htmlWidget {
    _widget ??= HtmlElementView(
      viewType: _getViewType(_viewId),
    );
    return _widget!;
  }

  static void lock() {}

  gmaps.MapsEventListener? _statusChangedListener;
  gmaps.MapsEventListener? _povChangedListener;
  gmaps.MapsEventListener? _zoomChangedListener;
  gmaps.MapsEventListener? _closeclickListener;

  Future<void> _setup(Map<String, dynamic> arg, [bool isReuse = false]) async {
    street_view.StreetViewPanoramaOptions options;
    String? errorMsg;
    try {
      options = await toStreetViewPanoramaOptions(arg);
    } catch (exception) {
      if (exception is NoStreetViewException) {
        NoStreetViewException noStreetViewException = exception;
        options = (noStreetViewException.options..visible = false);
        errorMsg = noStreetViewException.errorMsg;
        // Delay sending error to ensure stream listener is subscribed
        // The listener is set up asynchronously, so we need to wait a bit
        Future.delayed(Duration(milliseconds: 100), () {
          _methodChannel.invokeMethod("pano#onChange", {"error": errorMsg});
        });
      } else {
        // Handle other exceptions (like TypeError from cast failures)
        // Re-throw if it's not a NoStreetViewException
        rethrow;
      }
    }

    Completer<bool> initDone = Completer();
    if (!isReuse) {
      _streetViewPanorama = street_view.StreetViewPanorama(
        _div,
        options,
      );
    } else {
      //reuse _streetViewPanorama
      //set to invisible before init, then set visible after init done.
      street_view.StreetViewPanoramaOptions fakeOptions;
      try {
        fakeOptions = (await toStreetViewPanoramaOptions(arg)
          ..visible = false);
      } catch (exception) {
        if (exception is NoStreetViewException) {
          NoStreetViewException noStreetViewException = exception;
          fakeOptions = (noStreetViewException.options..visible = false);
          errorMsg = noStreetViewException.errorMsg;
          // Delay sending error to ensure stream listener is subscribed
          // The listener is set up asynchronously, so we need to wait a bit
          Future.delayed(Duration(milliseconds: 100), () {
            _methodChannel.invokeMethod("pano#onChange", {"error": errorMsg});
          });
        } else {
          // Handle other exceptions (like TypeError from cast failures)
          // Re-throw if it's not a NoStreetViewException
          rethrow;
        }
      }
      _streetViewPanorama.options = fakeOptions;
    }
    if (options.visible != null && !options.visible!) {
      //visible set to false can't trigger onStatusChanged
      //just set initDone to true
      initDone.complete(true);
    } else {
      late StreamSubscription initWatchDog;
      initWatchDog = _streetViewPanorama.onStatusChanged.listen((event) {
        initWatchDog.cancel();
        initDone.complete(true);
        //delay visible to avoid show pre-pano
        if (isReuse && options.visible!) {
          _streetViewPanorama.options = street_view.StreetViewPanoramaOptions()..visible = options.visible;
        }
      });
    }
    initDone.future.then((done) {
      _updateStatus(options);
      _streetViewInit = true;
      _setupListener();
      if (_viewReadyResult != null) {
        _viewReadyResult!.complete(_streetViewIsReady());
        _viewReadyResult = null;
      }
      // Also send error after initialization completes to ensure it's received
      // (in case the immediate send above was too early)
      if (errorMsg != null) {
        _methodChannel.invokeMethod("pano#onChange", {"error": errorMsg});
      }
    });
  }

  factory FlutterGoogleStreetViewPlugin.init(Map<String, dynamic> arg) => _lockMap.let((it) {
        FlutterGoogleStreetViewPlugin? plugin;
        it.forEach((viewId, inUse) {
          if (!inUse && plugin == null) {
            plugin = _plugins[viewId]!.also((it) {
              it._setup(arg, true);
              it.debug("reuse plugin viewId:${it.viewId}");
            });
          }
        });
        plugin ??= FlutterGoogleStreetViewPlugin(arg);
        _lockMap[plugin!.viewId] = true;
        return plugin;
      });

  FlutterGoogleStreetViewPlugin(Map<String, dynamic> arg) {
    debug("FlutterGoogleStreetViewPlugin:$arg");
    _viewId = _streetViewId += 1;
    debug("create new plugin, viewId:$viewId");
    _div = (DivElement()
      ..id = _getViewType(_viewId)
      ..style.width = '100%'
      ..style.height = '100%') as HTMLElement;
    _divs[_viewId] = _div;
    _plugins[_viewId] ??= this;
    ui.platformViewRegistry.registerViewFactory(
      _getViewType(_viewId),
      (int viewId) => _div,
    );
    // Create method channel BEFORE calling _setup so errors can be sent immediately
    _methodChannel = MethodChannel(
      'flutter_google_street_view_$viewId',
      const StandardMethodCodec(),
      registrar,
    );
    _methodChannel.setMethodCallHandler(_handleMethodCall);
    _setup(arg);
  }

  Type get _dTag => runtimeType;
  late street_view.StreetViewPanorama _streetViewPanorama;
  late MethodChannel _methodChannel;
  Timer? _animator;
  DateTime? _animatorRunTimestame;

  bool _streetViewInit = false;
  Completer? _viewReadyResult;
  bool _isStreetNamesEnabled = true;
  bool _isUserNavigationEnabled = true;
  bool _isAddressControl = true;
  bool _isDisableDefaultUI = false;
  bool _isDisableDoubleClickZoom = false;
  bool _isEnableCloseButton = true;
  bool _isFullscreenControl = true;
  bool _isLinksControl = true;
  bool _isMotionTracking = true;
  bool _isMotionTrackingControl = true;
  bool _isScrollwheel = true;
  bool _isPanControl = true;
  bool _isZoomControl = true;
  bool _isVisible = true;

  void dispose() {
    _animator?.cancel();
    _releaseListener();
    _lockMap[viewId] = false;
    _streetViewPanorama.options = street_view.StreetViewPanoramaOptions()
      //set to invisible
      ..visible = false
      // reset control setting
      ..position = null
      ..pano = null
      ..showRoadLabels = true
      ..clickToGo = true
      ..addressControl = true
      ..disableDefaultUI = true
      ..disableDoubleClickZoom = false
      ..enableCloseButton = false
      ..fullscreenControl = true
      ..linksControl = true
      ..motionTracking = true
      ..motionTrackingControl = true
      ..scrollwheel = true
      ..panControl = true
      ..zoomControl = true
      ..pov = (street_view.StreetViewPov()
        ..heading = 0
        ..pitch = 0)
      ..zoom = 1;
  }

  //callback fun doc(https://developers.google.com/maps/documentation/javascript/reference/3.44/street-view#StreetViewPanorama-Events)
  void _setupListener() {
    _releaseListener();

    _statusChangedListener = _streetViewPanorama.addListener(
      "status_changed",
      (() {
        try {
          _methodChannel.invokeMethod("pano#onChange", _getLocation());
        } catch (exception) {
          // Handle errors when getting location (e.g., no panorama available)
          String errorMsg = exception.toString();
          if (errorMsg.contains('ZERO_RESULTS') ||
              errorMsg.contains('STREETVIEW_GET_PANORAMA') ||
              errorMsg.contains('no panoramas')) {
            _methodChannel
                .invokeMethod("pano#onChange", {"error": "No panoramas found that match the search criteria."});
          } else {
            // For other errors, still send the error to the user
            _methodChannel.invokeMethod("pano#onChange", {"error": errorMsg});
          }
        }
      }).toJS,
    );
    _povChangedListener = _streetViewPanorama.addListener(
      "pov_changed",
      (() {
        _methodChannel.invokeMethod("camera#onChange", _getPanoramaCamera());
      }).toJS,
    );
    _zoomChangedListener = _streetViewPanorama.addListener(
      "zoom_changed",
      (() {
        _methodChannel.invokeMethod("camera#onChange", _getPanoramaCamera());
      }).toJS,
    );
    _closeclickListener = _streetViewPanorama.addListener(
      "closeclick",
      (() {
        _methodChannel.invokeMethod("close#onClick", true);
      }).toJS,
    );
  }

  void _releaseListener() {
    if (_statusChangedListener != null) {
      _statusChangedListener?.remove();
      _statusChangedListener = null;
    }
    if (_povChangedListener != null) {
      _povChangedListener?.remove();
      _povChangedListener = null;
    }
    if (_zoomChangedListener != null) {
      _zoomChangedListener?.remove();
      _zoomChangedListener = null;
    }
    if (_closeclickListener != null) {
      _closeclickListener?.remove();
      _closeclickListener = null;
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    final arg = call.arguments;
    debug("FlutterGoogleStreetViewPlugin:${call.method}, arg:$arg");
    Completer result = Completer();

    switch (call.method) {
      case 'streetView#waitForStreetView':
        return _streetViewInit
            ? _streetViewIsReady()
            : result.let((it) {
                _viewReadyResult = result;
                return result.future;
              });
      case "streetView#updateOptions":
        return _updateInitOptions(arg);
      case "streetView#animateTo":
        _animateTo(arg);
        return Future.value(true);
      case "streetView#getLocation":
        return Future.value(_getLocation());
      case "streetView#getPanoramaCamera":
        return Future.value(_getPanoramaCamera());
      case "streetView#isPanningGesturesEnabled":
        return Future.value(true);
      case "streetView#isStreetNamesEnabled":
        return Future.value(_isStreetNamesEnabled);
      case "streetView#isUserNavigationEnabled":
        return Future.value(_isUserNavigationEnabled);
      case "streetView#isZoomControl":
        return Future.value(_isZoomControl);
      case "streetView#movePos":
        _setPosition(arg);
        return Future.value();
      case "streetView#setStreetNamesEnabled":
        _setStreetNamesEnabled(arg);
        return Future.value();
      case "streetView#setUserNavigationEnabled":
        _setUserNavigationEnabled(arg);
        return Future.value();
      case "streetView#setAddressControl":
        _setAddressControl(arg);
        return Future.value();
      case "streetView#setAddressControlOptions":
        _setAddressControlOptions(arg);
        return Future.value();
      case "streetView#setDisableDefaultUI":
        _setDisableDefaultUI(arg);
        return Future.value();
      case "streetView#setDisableDoubleClickZoom":
        _setDisableDoubleClickZoom(arg);
        return Future.value();
      case "streetView#setEnableCloseButton":
        _setEnableCloseButton(arg);
        return Future.value();
      case "streetView#setFullscreenControl":
        _setFullscreenControl(arg);
        return Future.value();
      case "streetView#setFullscreenControlOptions":
        _setFullscreenControlOptions(arg);
        return Future.value();
      case "streetView#setLinksControl":
        _setLinksControl(arg);
        return Future.value();
      case "streetView#setMotionTracking":
        _setMotionTracking(arg);
        return Future.value();
      case "streetView#setMotionTrackingControl":
        _setMotionTrackingControl(arg);
        return Future.value();
      case "streetView#setMotionTrackingControlOptions":
        _setMotionTrackingControlOptions(arg);
        return Future.value();
      case "streetView#setPanControl":
        _setPanControl(arg);
        return Future.value();
      case "streetView#setPanControlOptions":
        _setPanControlOptions(arg);
        return Future.value();
      case "streetView#setScrollwheel":
        _setScrollwheel(arg);
        return Future.value();
      case "streetView#setZoomControl":
        _setZoomControl(arg);
        return Future.value();
      case "streetView#setZoomControlOptions":
        _setZoomControlOptions(arg);
        return Future.value();
      case "streetView#setVisible":
        _setVisible(arg);
        return Future.value();
    }
  }
}

extension FlutterGoogleStreetViewPluginExtension on FlutterGoogleStreetViewPlugin {
  void debug(String log) {
    if (FlutterGoogleStreetViewPlugin._debug) print("$_dTag: $log");
  }

  Future<Map<String, dynamic>> _streetViewIsReady() => Future.value({
        "isStreetNamesEnabled": _isStreetNamesEnabled,
        "isUserNavigationEnabled": _isUserNavigationEnabled,
        "isAddressControl": _isAddressControl,
        "isDisableDefaultUI": _isDisableDefaultUI,
        "isDisableDoubleClickZoom": _isDisableDoubleClickZoom,
        "isEnableCloseButton": _isEnableCloseButton,
        "isFullscreenControl": _isFullscreenControl,
        "isLinksControl": _isLinksControl,
        "isMotionTracking": _isMotionTracking,
        "isMotionTrackingControl": _isMotionTrackingControl,
        "isScrollwheel": _isScrollwheel,
        "isPanControl": _isPanControl,
        "isZoomControl": _isZoomControl,
        "isVisible": _isVisible,
        "streetViewCount": FlutterGoogleStreetViewPlugin._plugins.length,
      });

  Future<Map<String, dynamic>> _updateInitOptions(Map arg) async {
    street_view.StreetViewPanoramaOptions options = street_view.StreetViewPanoramaOptions();
    options = await _setPosition(arg, options: options, toApply: false);
    options = _setStreetNamesEnabled(arg, options: options, toApply: false);
    options = _setUserNavigationEnabled(arg, options: options, toApply: false);
    options = _animateTo(arg, options: options, toApply: false);
    options = _setAddressControl(arg, options: options, toApply: false);
    options = _setAddressControlOptions(arg, options: options, toApply: false);
    options = _setDisableDefaultUI(arg, options: options, toApply: false);
    options = _setDisableDoubleClickZoom(arg, options: options, toApply: false);
    options = _setEnableCloseButton(arg, options: options, toApply: false);
    options = _setFullscreenControl(arg, options: options, toApply: false);
    options = _setFullscreenControlOptions(arg, options: options, toApply: false);
    options = _setLinksControl(arg, options: options, toApply: false);
    options = _setMotionTracking(arg, options: options, toApply: false);
    options = _setMotionTrackingControl(arg, options: options, toApply: false);
    options = _setMotionTrackingControlOptions(arg, options: options, toApply: false);
    options = _setScrollwheel(arg, options: options, toApply: false);
    options = _setPanControl(arg, options: options, toApply: false);
    options = _setPanControlOptions(arg, options: options, toApply: false);
    options = _setZoomControl(arg, options: options, toApply: false);
    options = _setZoomControlOptions(arg, options: options, toApply: false);
    options = _setVisible(arg, options: options, toApply: false);
    _apply(options);
    return _streetViewIsReady();
  }

  street_view.StreetViewPanoramaOptions _animateTo(
    Map arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    final currentPov = _streetViewPanorama.pov;
    final bearingDef = currentPov.heading;
    final tiltDef = currentPov.pitch;
    final zoomDef = _streetViewPanorama.zoom;
    final bearingTarget = arg['bearing'] as double? ?? bearingDef;
    final tiltTarget = arg['tilt'] as double? ?? tiltDef;
    final zoomTarget = arg['zoom'] as double? ?? zoomDef;
    options0.pov = street_view.StreetViewPov()
      ..heading = bearingTarget
      ..pitch = tiltTarget;
    options0.zoom = (arg['zoom'] as double? ?? 0) + zoomTarget;

    if (toApply) {
      final duration = arg["duration"] as int?;
      if (duration != null) {
        if (_animator != null) {
          if (_animator!.isActive) _animator!.cancel();
          _animator = null;
        }
        _animatorRunTimestame = DateTime.now();
        final bearingDiff = bearingTarget - bearingDef;
        final tiltDiff = tiltTarget - tiltDef;
        final zoomDiff = zoomTarget - zoomDef;

        Timer.periodic(Duration(milliseconds: 15), (timer) {
          _animator ??= timer;
          final timeDis = DateTime.now().difference(_animatorRunTimestame!);
          final percent = min((timeDis.inMilliseconds / duration), 1);

          final bearingTarget = bearingDef + bearingDiff * percent;
          final tiltTarget = tiltDef + tiltDiff * percent;
          final zoomTarget = zoomDef + zoomDiff * percent;
          final povTarget = street_view.StreetViewPov()
            ..heading = bearingTarget
            ..pitch = tiltTarget;
          _streetViewPanorama.pov = povTarget;
          _streetViewPanorama.zoom = zoomTarget;

          if (percent == 1) {
            timer.cancel();
            _animator = null;
          }
        });
      }
    }
    return options0;
  }

  Map<String, dynamic> _getLocation() => streetViewPanoramaLocationToJson(_streetViewPanorama);

  Map<String, dynamic> _getPanoramaCamera() => streetViewPanoramaCameraToJson(_streetViewPanorama);

  Future<street_view.StreetViewPanoramaOptions> _setPosition(
    Map arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) async {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();

    double? raduis = arg['radius'] as double?;
    String? source = arg['source'] as String?;
    JSObject request;
    gmaps.LatLng? location;
    String? pano;
    if (arg['panoId'] != null) {
      pano = arg['panoId'];
      request = street_view.StreetViewPanoRequest()..pano = pano;
    } else {
      location =
          arg['position'] != null ? gmaps.LatLng(arg['position'][0], arg['position'][1]) : _streetViewPanorama.position;
      final sourceTmp =
          source == "outdoor" ? street_view.StreetViewSource.OUTDOOR : street_view.StreetViewSource.DEFAULT;
      request = street_view.StreetViewLocationRequest()
        ..location = location
        ..radius = raduis
        ..source = sourceTmp;
    }
    try {
      final data = await street_view.StreetViewService().getPanorama(request);

      // Check if location is null - this indicates no panorama was found
      if (data.data.location == null) {
        // No panorama found - create error
        String errorMsg = location != null
            ? "No panoramas found that match the search criteria for position:${location.lat}, ${location.lng}."
            : pano != null
                ? "No panoramas found that match the search criteria for panoId:$pano."
                : "No panoramas found that match the search criteria.";

        // Create StreetViewPanoramaException with proper error information
        final customException = StreetViewPanoramaException(
          originalError: "Location is null - no panorama found",
          message: "StreetViewPanoramaException: $errorMsg",
          location: location,
          panoId: pano,
          errorCode: 'ZERO_RESULTS',
        );

        // Send error event with custom message
        _methodChannel.invokeMethod("pano#onChange", {"error": customException.message});
      } else {
        // Success - set the location or pano
        if (location != null) {
          options0.position = data.data.location!.latLng;
        } else {
          options0.pano = data.data.location!.pano;
        }
      }
    } catch (exception) {
      // Handle MapsRequestError or other exceptions from getPanorama
      String errorMsg;
      String? errorCode;

      if (exception is StreetViewPanoramaException) {
        // Use the custom exception's message
        errorMsg = exception.message;
        errorCode = exception.errorCode;
      } else {
        String errorMessage = exception.toString();
        if (errorMessage.contains('ZERO_RESULTS')) {
          errorCode = 'ZERO_RESULTS';
        } else if (errorMessage.contains('STREETVIEW_GET_PANORAMA')) {
          errorCode = 'STREETVIEW_GET_PANORAMA';
        }

        if (errorCode != null) {
          // Create custom exception with detailed information
          final customException = StreetViewPanoramaException(
            originalError: errorMessage,
            message: location != null
                ? "StreetViewPanoramaException: No panoramas found that match the search criteria for position: ${location.lat}, ${location.lng}. Try changing `position`, `radius`, or `source`."
                : pano != null
                    ? "StreetViewPanoramaException: No panoramas found that match the search criteria for panoId: $pano. Try changing `panoId`."
                    : "StreetViewPanoramaException: No panoramas found that match the search criteria.",
            location: location,
            panoId: pano,
            errorCode: errorCode,
          );
          errorMsg = customException.message;
        } else {
          // For other errors, use the exception message
          errorMsg = errorMessage;
        }
      }

      // Send error event with custom message
      _methodChannel.invokeMethod("pano#onChange", {"error": errorMsg});
    }
    if (toApply) _apply(options0);
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setStreetNamesEnabled(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['streetNamesEnabled'] : arg) as bool? ?? _isStreetNamesEnabled;
    options0.showRoadLabels = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setUserNavigationEnabled(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['userNavigationEnabled'] : arg) as bool? ?? _isUserNavigationEnabled;
    options0.clickToGo = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setAddressControl(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['addressControl'] : arg) as bool? ?? _isAddressControl;
    options0.addressControl = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setAddressControlOptions(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    String? position = arg is Map ? arg['addressControlOptions'] : arg as String?;
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    options0.addressControlOptions = street_view.StreetViewAddressControlOptions()
      ..position = toControlPosition(position);
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setDisableDefaultUI(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['disableDefaultUI'] : arg) as bool? ?? _isDisableDefaultUI;
    options0.disableDefaultUI = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setDisableDoubleClickZoom(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['disableDoubleClickZoom'] : arg) as bool? ?? _isDisableDoubleClickZoom;
    options0.disableDoubleClickZoom = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setEnableCloseButton(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['enableCloseButton'] : arg) as bool? ?? _isEnableCloseButton;
    options0.enableCloseButton = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setFullscreenControl(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['fullscreenControl'] : arg) as bool? ?? _isFullscreenControl;
    options0.fullscreenControl = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setFullscreenControlOptions(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    String? position = arg is Map ? arg['fullscreenControlOptions'] : arg as String?;
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    options0.fullscreenControlOptions = gmaps.FullscreenControlOptions()..position = toControlPosition(position);
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setLinksControl(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['linksControl'] : arg) as bool? ?? _isLinksControl;
    options0.linksControl = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setMotionTracking(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['motionTracking'] : arg) as bool? ?? _isMotionTracking;
    options0.motionTracking = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setMotionTrackingControl(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['motionTrackingControl'] : arg) as bool? ?? _isMotionTrackingControl;
    options0.motionTrackingControl = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setMotionTrackingControlOptions(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    String? position = arg is Map ? arg['motionTrackingControlOptions'] : arg as String?;
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    options0.motionTrackingControlOptions = gmaps.MotionTrackingControlOptions()
      ..position = toControlPosition(position);
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setPanControl(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['panControl'] : arg) as bool? ?? _isPanControl;
    options0.panControl = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setPanControlOptions(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    String? position = arg is Map ? arg['panControlOptions'] : arg as String?;
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    options0.panControlOptions = gmaps.PanControlOptions()..position = toControlPosition(position);
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setScrollwheel(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['scrollwheel'] : arg) as bool? ?? _isScrollwheel;
    options0.scrollwheel = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setZoomControl(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['zoomControl'] : arg) as bool? ?? _isZoomControl;
    options0.zoomControl = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setZoomControlOptions(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    String? position = arg is Map ? arg['zoomControlOptions'] : arg as String?;
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    options0.zoomControlOptions = gmaps.ZoomControlOptions()..position = toControlPosition(position);
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  street_view.StreetViewPanoramaOptions _setVisible(
    dynamic arg, {
    street_view.StreetViewPanoramaOptions? options,
    bool toApply = true,
  }) {
    final options0 = options ?? street_view.StreetViewPanoramaOptions();
    bool enable = (arg is Map ? arg['scrollwheel'] : arg) as bool? ?? _isVisible;
    options0.visible = enable;
    if (toApply) {
      _apply(options0);
    }
    return options0;
  }

  void _apply(street_view.StreetViewPanoramaOptions options) {
    _streetViewPanorama.options = options;
    _updateStatus(options);
  }

  void _updateStatus(street_view.StreetViewPanoramaOptions options) {
    if (options.showRoadLabels != null) {
      _isStreetNamesEnabled = options.showRoadLabels!;
    }
    if (options.clickToGo != null) {
      _isUserNavigationEnabled = options.clickToGo!;
    }
    if (options.addressControl != null) {
      _isAddressControl = options.addressControl!;
    }
    if (options.disableDefaultUI != null) {
      _isDisableDefaultUI = options.disableDefaultUI!;
    }
    if (options.disableDoubleClickZoom != null) {
      _isDisableDoubleClickZoom = options.disableDoubleClickZoom!;
    }
    if (options.enableCloseButton != null) {
      _isEnableCloseButton = options.enableCloseButton!;
    }
    if (options.fullscreenControl != null) {
      _isFullscreenControl = options.fullscreenControl!;
    }
    if (options.linksControl != null) _isLinksControl = options.linksControl!;
    if (options.motionTracking != null) {
      _isMotionTracking = options.motionTracking!;
    }
    if (options.motionTrackingControl != null) {
      _isMotionTrackingControl = options.motionTrackingControl!;
    }
    if (options.scrollwheel != null) _isScrollwheel = options.scrollwheel!;
    if (options.panControl != null) _isPanControl = options.panControl!;
    if (options.zoomControl != null) _isZoomControl = options.zoomControl!;
    if (options.visible != null) _isVisible = options.visible!;
  }
}
