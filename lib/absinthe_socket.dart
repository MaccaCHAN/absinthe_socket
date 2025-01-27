library absinthe_socket;

import 'dart:async';

import 'package:phoenix_wings/phoenix_wings.dart';

/// An Absinthe Socket
class AbsintheSocket {

  AbsintheSocket(this.endpoint, {this.socketOptions}) {
    if (socketOptions == null) socketOptions = AbsintheSocketOptions();
    subscriptionHandler = NotifierPushHandler(
        onError: _onError,
        onTimeout: _onTimeout,
        onSucceed: _onSubscriptionSucceed );
    unsubscriptionHandler = NotifierPushHandler(
        onError: _onError,
        onTimeout: _onTimeout,
        onSucceed: _onUnsubscriptionSucceed );
    _phoenixSocket = PhoenixSocket(endpoint,
        socketOptions: PhoenixSocketOptions(
            params: socketOptions!.params..addAll({"vsn": "2.0.0"})));
    _connect();
  }

  String endpoint;
  AbsintheSocketOptions? socketOptions = AbsintheSocketOptions();
  PhoenixSocket? _phoenixSocket;
  PhoenixChannel? _absintheChannel;
  List<Notifier> _notifiers = [];
  List<Notifier> _queuedPushes = [];
  NotifierPushHandler? subscriptionHandler;
  NotifierPushHandler? unsubscriptionHandler;

  static  _onError(Map? response) {
    print("onError");
    print(response.toString());
  }

  static _onSubscriptionSucceed(Notifier notifier) {
    return (Map? response) {
      print("response");
      print(response.toString());
      notifier.subscriptionId = response?["subscriptionId"];
    };
  }

  _onUnsubscriptionSucceed(Notifier notifier) {
    return (Map? response) {
      print("unsubscription response");
      print(response.toString());
      notifier.cancel();
      _notifiers.remove(notifier);
    };
  }

  static _onTimeout(Map? response) {
    print("onTimeout");
  }



  _connect() async {
    if (_phoenixSocket != null) {
      await _phoenixSocket!.connect();
      _phoenixSocket!.onMessage(_onMessage);
      _absintheChannel = _phoenixSocket!.channel("__absinthe__:control", {});
      _absintheChannel!.join()?.receive("ok", _sendQueuedPushes);
      }
    }

  disconnect() {
    _phoenixSocket?.disconnect();
  }

  _sendQueuedPushes(_) {
    _queuedPushes.forEach((notifier) {
      _pushRequest(notifier);
    });
    _queuedPushes = [];
  }

  void cancel(Notifier notifier) {
    unsubscribe(notifier);
  }

  void unsubscribe(Notifier notifier) {
    if (_absintheChannel != null && unsubscriptionHandler != null) {
      _handlePush(
          _absintheChannel!.push(
              event: "unsubscribe",
              payload: {"subscriptionId": notifier.subscriptionId})!,
          _createPushHandler(unsubscriptionHandler!, notifier));
    }
  }

  Notifier send(GqlRequest request) {
    Notifier notifier = Notifier(request: request);
    _notifiers.add(notifier);
    _pushRequest(notifier);
    return notifier;
  }

  _onMessage(PhoenixMessage message) {
    String subscriptionId = message.topic!;
    _notifiers
        .where((Notifier notifier) => notifier.subscriptionId == subscriptionId)
        .forEach(
            (Notifier notifier) => notifier.notify(message.payload!["result"]));
  }

  _pushRequest(Notifier notifier) {
    if (_absintheChannel == null && subscriptionHandler != null) {
      _queuedPushes.add(notifier);
    } else {
      _handlePush(
          _absintheChannel!.push(
              event: "doc", payload: {"query": notifier.request.operation})!,
          _createPushHandler(subscriptionHandler!, notifier));
    }
  }

  _handlePush(PhoenixPush push, PushHandler handler) {
    push
        .receive("ok", handler.onSucceed)
        .receive("error", handler.onError)
        .receive("timeout", handler.onTimeout);
  }

  PushHandler _createPushHandler(
      NotifierPushHandler notifierPushHandler, Notifier notifier) {
    return _createEventHandler(notifier, notifierPushHandler);
  }

  _createEventHandler(
      Notifier notifier, NotifierPushHandler notifierPushHandler) {
    return PushHandler(
        onError: notifierPushHandler.onError,
        onSucceed: notifierPushHandler.onSucceed(notifier),
        onTimeout: notifierPushHandler.onTimeout);
  }
}

class AbsintheSocketOptions {
  Map<String, String> params;

  AbsintheSocketOptions({this.params = const {}}) ;
}

class Notifier<Result> {
  GqlRequest request;
  List<Observer<Result>> observers = [];
  String? subscriptionId;

  Notifier({required this.request});

  void observe(Observer<Result> observer) {
    observers.add(observer);
  }

  void notify(Map result) {

    observers.forEach((Observer observer) => observer.onResult != null ? observer.onResult!(result) : null );
  }

  void cancel() {
    observers.forEach((Observer observer) =>observer.onCancel != null ?  observer.onCancel!() : null);
  }
}

late StreamController hi;

class Observer<Result> {
  Function? onAbort;
  Function? onCancel;
  Function? onError;
  Function? onStart;
  Function? onResult;

  Observer(
      {this.onAbort, this.onCancel, this.onError, this.onStart, this.onResult});
}

class GqlRequest {
  String operation;

  GqlRequest({required this.operation});
}

class NotifierPushHandler<Response> {
  dynamic Function(Map?) onError;
  dynamic Function(Notifier) onSucceed;
  dynamic Function(Map?) onTimeout;

  NotifierPushHandler({required this.onError, required this.onSucceed, required this.onTimeout});
}

class PushHandler<Response> {
  dynamic Function(Map?) onError;
  dynamic Function(Map?) onSucceed;
  dynamic Function(Map?) onTimeout;

  PushHandler({required this.onError, required this.onSucceed, required this.onTimeout});
}
