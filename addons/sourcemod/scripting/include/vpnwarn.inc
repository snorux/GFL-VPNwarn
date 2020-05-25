#if defined _vpnwarn_included_
  #endinput
#endif
#define _vpnwarn_included_

/**
 * Check if a given client is using a VPN or not.
 *
 * @param client	The client to check.
 * @return			True if the provided client is using a VPN, false otherwise.
 */
native bool ClientUsingVPN(int client);