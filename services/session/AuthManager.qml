pragma Singleton

import QtQuick
import Quickshell.Services.Pam

import qs.config

// PAM authentication (Quickshell's PamContext, "login" stack) for the
// built-in lockscreen. authenticationSucceeded is the only thing that may
// unlock it (see shell/Lockscreen.qml).
QtObject {
  id: root

  property bool isAuthenticating: false
  // What to show under the password field ("" for nothing)
  property string message: ""
  property bool messageIsError: false

  signal authenticationSucceeded
  signal authenticationFailed(string reason)
  signal authenticationError(string error)

  // Starts checking `password`; false if it can't start (one is already
  // running, the password is empty, or PAM wouldn't start)
  function authenticate(password) {
    if (root.isAuthenticating)
      return false;
    if (!password) {
      root._show(I18n.tr("Please enter a password"), true);
      return false;
    }
    root.isAuthenticating = true;
    root._password = password;
    root._show(I18n.tr("Authenticating..."), false);
    if (!_pam.start()) {
      root._end(I18n.tr("Failed to start authentication"), true);
      return false;
    }
    return true;
  }

  function cancel() {
    if (!root.isAuthenticating || !_pam.active)
      return;
    _pam.abort();
    root._end("", false);
  }

  function clearMessage() {
    root._show("", false);
  }

  // -- Private --

  // Only held while PAM may ask for it
  property string _password: ""

  function _show(text, isError) {
    root.message = text;
    root.messageIsError = isError;
  }

  // An attempt is over: forget the password and show the outcome
  function _end(text, isError) {
    root.isAuthenticating = false;
    root._password = "";
    root._show(text, isError);
  }

  property PamContext _pam: PamContext {
    config: "login"

    onCompleted: result => {
      switch (result) {
      case PamResult.Success:
        root._end("", false);
        root.authenticationSucceeded();
        break;
      case PamResult.Failed:
        root._end(I18n.tr("Authentication failed"), true);
        root.authenticationFailed("Authentication failed");
        break;
      case PamResult.MaxTries:
        root._end(I18n.tr("Maximum attempts exceeded"), true);
        root.authenticationFailed("Maximum attempts exceeded");
        break;
      default:
        root._end(I18n.tr("Authentication error occurred"), true);
        root.authenticationError("Authentication error occurred");
      }
    }

    // A prompt ("Password: ") is answered, not shown: it would replace
    // "Authenticating..." while the password is checked
    onPamMessage: {
      if (responseRequired) {
        root._pam.respond(root._password);
        return;
      }
      if (message !== "")
        root._show(message, messageIsError);
    }

    onError: error => {
      let text = "";
      switch (error) {
      case PamError.StartFailed:
        text = I18n.tr("Failed to start authentication");
        break;
      case PamError.TryAuthFailed:
        text = I18n.tr("Failed to authenticate");
        break;
      case PamError.InternalError:
        text = I18n.tr("Internal error occurred");
        break;
      }
      root._end(text, true);
      root.authenticationError(text);
    }
  }
}
