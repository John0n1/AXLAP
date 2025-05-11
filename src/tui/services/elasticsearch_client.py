from elasticsearch import Elasticsearch, exceptions

class AXLAPElasticsearchClient:
    def __init__(self, config):
        self.host = config.get('elasticsearch', 'host', fallback='127.0.0.1')
        self.port = config.getint('elasticsearch', 'port', fallback=9200)
        self.scheme = config.get('elasticsearch', 'scheme', fallback='http')
        # Placeholder for future auth/SSL settings from config
        # self.use_ssl = config.getboolean('elasticsearch', 'use_ssl', fallback=False)
        # self.ca_certs = config.get('elasticsearch', 'ca_certs', fallback=None)
        # self.http_auth_user = config.get('elasticsearch', 'user', fallback=None)
        # self.http_auth_pass = config.get('elasticsearch', 'password', fallback=None)

        connection_params = {
            'host': self.host,
            'port': self.port,
            'scheme': self.scheme,
            # 'use_ssl': self.use_ssl,
            # 'ca_certs': self.ca_certs,
            # 'verify_certs': True if self.ca_certs else False,
        }
        # if self.http_auth_user and self.http_auth_pass:
        #     connection_params['http_auth'] = (self.http_auth_user, self.http_auth_pass)

        try:
            self.es = Elasticsearch([connection_params], timeout=10, max_retries=2, retry_on_timeout=True)
            if not self.es.ping():
                # This specific error might be better for the TUI to display
                self.es = None # Ensure es is None if ping fails
                print(f"ERROR: Elasticsearch ping failed for {self.scheme}://{self.host}:{self.port}. Client disabled.")
                # Consider raising a custom exception or returning a status for the TUI to handle
            else:
                print(f"Successfully connected to Elasticsearch at {self.scheme}://{self.host}:{self.port}")
        except exceptions.ConnectionError as e:
            self.es = None
            print(f"ERROR: Elasticsearch connection error for {self.scheme}://{self.host}:{self.port} - {e}. Client disabled.")
        except Exception as e: # Catch any other unexpected errors during initialization
            self.es = None
            print(f"ERROR: Unexpected error initializing Elasticsearch client for {self.scheme}://{self.host}:{self.port} - {e}. Client disabled.")

    def is_connected(self):
        """Check if the Elasticsearch client is connected."""
        return self.es is not None and self.es.ping()

    def search(self, index_pattern, query_body, size=10, sort_criteria=None):
        if not self.is_connected():
            print("Elasticsearch client not connected. Cannot perform search.")
            return {"hits": {"hits": [], "total": {"value": 0, "relation": "eq"}}, "timed_out": False, "took": 0}
        
        # Simplified default sort. Callers can provide specific sort_criteria.
        if sort_criteria is None:
            sort_criteria = [{"@timestamp": "desc"}] # Common default

        search_params = {
            "index": index_pattern,
            "body": query_body,
            "size": size,
            "sort": sort_criteria,
            "ignore_unavailable": True,
            "allow_no_indices": True
        }
        try:
            return self.es.search(**search_params)
        except exceptions.ElasticsearchException as e:
            print(f"Elasticsearch search error on index '{index_pattern}': {e}")
            return {"hits": {"hits": [], "total": {"value": 0, "relation": "eq"}}, "timed_out": False, "took": 0, "error": str(e)}

    def count(self, index_pattern, query_body=None):
        if not self.is_connected():
            print("Elasticsearch client not connected. Cannot perform count.")
            return {"count": 0}
        
        if query_body is None:
            query_body = {"query": {"match_all": {}}}
        
        count_params = {
            "index": index_pattern,
            "body": query_body,
            "ignore_unavailable": True,
            "allow_no_indices": True
        }
        try:
            return self.es.count(**count_params)
        except exceptions.ElasticsearchException as e:
            print(f"Elasticsearch count error on index '{index_pattern}': {e}")
            return {"count": 0, "error": str(e)}

    def get_document(self, index_name, doc_id, ignore_not_found=True):
        if not self.is_connected():
            print("Elasticsearch client not connected. Cannot get document.")
            return None
        try:
            return self.es.get(index=index_name, id=doc_id)
        except exceptions.NotFoundError:
            if not ignore_not_found:
                print(f"Document {doc_id} not found in index {index_name}.")
            return None
        except exceptions.ElasticsearchException as e:
            print(f"Error getting document {doc_id} from index {index_name}: {e}")
            return None
