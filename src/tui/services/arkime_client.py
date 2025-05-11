import requests
import json
# from base64 import b64encode # Uncomment if basic auth example is used

class ArkimeClient:
    def __init__(self, config):
        # Extract Arkime connection details from the TUI config object
        self.verify_ssl = config.get('ARKIME_VERIFY_SSL', False)  # Option to disable SSL verification (for self-signed certs)
        # Add authentication if needed (e.g., API key or user/pass)
        # self.auth = (config['ARKIME_USER'], config['ARKIME_PASSWORD'])  # Example with basic auth
        self.auth = None  # Placeholder, adjust as needed

    def search_sessions(self, query_string="", fields=["srcip", "dstip", "srcport", "dstport", "protocols", "node", "firstPacket", "lastPacket"], size=100):
        """
        Searches Arkime sessions based on a query string.

        Args:
            query_string (str): The search query (Arkime's query language).  e.g., "ip.src==192.168.1.100"
            fields (list):  List of fields to return for each session.
            size (int): Maximum number of results to return.

        Returns:
            list: A list of session dictionaries, or an empty list if no results or an error occurs.
        """
        url = f"{self.base_url}/api/search"
        params = {
            "expression": query_string,
            "fields": ",".join(fields),
            "size": size,
            "format": "json"  # Ensure JSON output
        }
        headers = {}
        if self.auth:
            # headers['Authorization'] = 'Basic ' + b64encode(f"{self.auth[0]}:{self.auth[1]}".encode()).decode("ascii") # Basic Auth example
            pass # Or set API key header, etc.

        try:
            response = requests.get(url, params=params, headers=headers, verify=self.verify_ssl)
            response.raise_for_status()  # Raise HTTPError for bad responses (4xx or 5xx)
            data = response.json()
            # Arkime API might have a nested structure, adjust this based on actual response:
            if "sessions" in data:
                return data["sessions"]
            elif isinstance(data, list): # If the top-level is already a list of sessions
                return data
            else:
                return []  # Unexpected format
        except requests.exceptions.RequestException as e:
            print(f"Error searching Arkime: {e}")
            return []  # Return empty list on error
