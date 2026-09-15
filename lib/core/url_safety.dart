/// 判断 [url] 是否为「非本地 http://」地址（API Key 将明文传输，需用户确认）。
///
/// 仅 `http` scheme 且 host 不是 localhost / 127.0.0.1 / ::1 时视为不安全；
/// https、无 scheme、畸形 URL 均返回 false（由其他校验兜底）。
bool isUnsafeHttpUrl(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.scheme != 'http') return false;
  final host = u.host.toLowerCase();
  return host != 'localhost' &&
      host != '127.0.0.1' &&
      host != '[::1]' &&
      host != '::1';
}
