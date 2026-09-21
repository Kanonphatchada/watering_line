import 'dart:html' as html;

void clearUrlQueryParams() {
  html.window.history.replaceState(null, '', '/');
}

void reloadPage() {
  html.window.location.reload();
}
