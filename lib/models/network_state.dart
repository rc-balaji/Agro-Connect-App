enum NetworkTransport {
  none,
  wifi,
  mobile,
  ethernet,
  vpn,
  bluetooth,
  satellite,
  other,
}

class NetworkState {
  const NetworkState({
    this.transport = NetworkTransport.none,
    this.hasInterface = false,
    this.internetReachable = false,
    this.lastChecked,
  });

  final NetworkTransport transport;
  final bool hasInterface;
  final bool internetReachable;
  final DateTime? lastChecked;

  String get label {
    switch (transport) {
      case NetworkTransport.wifi:
        return 'Wi-Fi';
      case NetworkTransport.mobile:
        return 'Mobile';
      case NetworkTransport.ethernet:
        return 'Ethernet';
      case NetworkTransport.vpn:
        return 'VPN';
      case NetworkTransport.bluetooth:
        return 'Bluetooth';
      case NetworkTransport.satellite:
        return 'Satellite';
      case NetworkTransport.other:
        return 'Other';
      case NetworkTransport.none:
        return 'No network';
    }
  }
}
