# axlap/src/tui/axlap_tui.py
import curses
import time
import os
from configparser import ConfigParser

# Import views
from views.dashboard_view import DashboardView
from views.query_view import QueryView 
from views.session_view import SessionView
from views.protocol_view import ProtocolView 
from views.plugin_view import PluginView 
#from views.graph_view import GraphView 

# Import services
from services.elasticsearch_client import AXLAPElasticsearchClient as ElasticsearchClient
from services.arkime_client import ArkimeClient as ArkimeClient
from services.opencti_client import OpenCTIClient


class AXLAPTUI:
        def __init__(self, stdscr):
            self.stdscr = stdscr
            curses.curs_set(0)  # Hide cursor
            curses.start_color()
            curses.use_default_colors() # Use terminal default background

            # Initialize color pairs
            # Pair 1: Default text on default background
            curses.init_pair(1, curses.COLOR_WHITE, -1) # Text, Background (-1 for default)
            curses.init_pair(2, curses.COLOR_GREEN, -1) # Highlight / Success
            curses.init_pair(3, curses.COLOR_RED, -1)   # Error / Alert
            curses.init_pair(4, curses.COLOR_YELLOW, -1) # Warning / Info
            curses.init_pair(5, curses.COLOR_BLUE, -1)   # Titles / Borders
            curses.init_pair(6, curses.COLOR_CYAN, -1)   # Interactive elements
            curses.init_pair(7, curses.COLOR_BLACK, curses.COLOR_WHITE) # Inverse for selection

            self.config = self._load_config()
            self.es_client = ElasticsearchClient(self.config)
            self.arkime_client = ArkimeClient(self.config)
         #   self.opencti_client = OpenCTIClient(self.config)

            self.views = {
                "dashboard": DashboardView(stdscr, self.config, self.es_client),
                "query": QueryView(stdscr, self.config, self.arkime_client, self.es_client), # Pass arkime_client
                "sessions": SessionView(stdscr, self.config, self.arkime_client),
                "protocols": ProtocolView(stdscr, self.config, self.es_client),
                "plugins": PluginView(stdscr, self.config), # No client needed for basic plugin view
                # "graph": GraphView(stdscr, self.config, self.opencti_client),
            }
            self.current_view_name = self.config.get('general', 'default_view', fallback='dashboard')
            self.current_view = self.views[self.current_view_name]
            
            self.running = True
            self.status_message = "AXLAP Initialized. Press 'q' to quit, 'h' for help."

        def _load_config(self):
            config = ConfigParser()
            # Determine path to config relative to this script or AXLAP_BASE_DIR
            script_dir = os.path.dirname(os.path.abspath(__file__))
            config_path = os.path.join(script_dir, '..', '..', 'config', 'axlap_tui_config.ini')
            if not os.path.exists(config_path):
                # Fallback if running from a different structure (e.g. install dir)
                config_path = "/opt/axlap/config/axlap_tui_config.ini"

            if not os.path.exists(config_path):
                raise FileNotFoundError(f"TUI Config file not found at {config_path}")
            
            config.read(config_path)
            
            # Substitute environment variables like OPENCTI_ADMIN_TOKEN
            if 'opencti' in config and 'api_key' in config['opencti']:
                token_placeholder = config['opencti']['api_key']
                if token_placeholder.startswith('${') and token_placeholder.endswith('}'):
                    env_var_name = token_placeholder[2:-1]
                    env_var_value = os.getenv(env_var_name)
                    if env_var_value:
                        config.set('opencti', 'api_key', env_var_value)
                    else:
                        # Try to get from fixed install.sh generated value if not in env
                        # This is a bit of a hack; ideally, config is fully resolved.
                        # For now, assume it's set in config or install script makes it available.
                        print(f"Warning: Environment variable {env_var_name} for OpenCTI API key not set.")
                        # Fallback to a known location if install.sh writes it there.
                        # This part requires a robust way to get the token if not directly in .ini
            return config

        def _draw_status_bar(self):
            h, w = self.stdscr.getmaxyx()
            status_bar_text = f"{self.status_message[:w-1]}"
            self.stdscr.attron(curses.color_pair(7)) # Inverse color for status bar
            self.stdscr.addstr(h - 1, 0, status_bar_text)
            self.stdscr.addstr(h - 1, len(status_bar_text), " " * (w - len(status_bar_text) -1))
            self.stdscr.attroff(curses.color_pair(7))

        def _draw_header_bar(self):
            h, w = self.stdscr.getmaxyx()
            title = f"AXLAP - {self.current_view_name.upper()} View"
            menu_options = "[D]ashboard [Q]uery [S]essions [P]lugins [G]raph | [H]elp [ESC]Quit"
            
            self.stdscr.attron(curses.color_pair(5) | curses.A_BOLD)
            self.stdscr.addstr(0, 0, title.ljust(w-1))
            self.stdscr.attroff(curses.color_pair(5) | curses.A_BOLD)

            # Right-align menu options
            start_menu_pos = w - len(menu_options) -1 
            if start_menu_pos < len(title) + 2 : start_menu_pos = len(title) + 2 # Avoid overlap

            self.stdscr.attron(curses.color_pair(6))
            self.stdscr.addstr(0, start_menu_pos, menu_options)
            self.stdscr.attroff(curses.color_pair(6))


        def run(self):
            self.stdscr.nodelay(True) # Non-blocking input
            self.stdscr.timeout(100) # Timeout for getch() in ms, allows periodic updates

            while self.running:
                h, w = self.stdscr.getmaxyx()
                self.stdscr.clear()

                self._draw_header_bar()
                
                # Delegate drawing to the current view
                # Views should draw within a sub-window or specified area
                view_window_height = h - 2 # Reserve 1 for header, 1 for status
                view_window_width = w
                
                try:
                    self.current_view.draw(view_window_height, view_window_width)
                except Exception as e:
                    self.status_message = f"Error in view '{self.current_view_name}': {str(e)[:50]}"
                    # Log full error to a file
                    with open("/tmp/axlap_tui_error.log", "a") as f_err:
                        f_err.write(f"{time.asctime()}: View: {self.current_view_name}, Error: {e}\n")


                self._draw_status_bar()
                self.stdscr.refresh()

                try:
                    key = self.stdscr.getch()
                except curses.error: # E.g. if window resized too small
                    key = -1 

                if key != -1:
                    self.handle_global_input(key)
                    if self.running: # Global input might set running to False
                        self.current_view.handle_input(key)
                
                # Allow views to have their own update logic (e.g., dashboard refresh)
                if hasattr(self.current_view, 'update') and callable(self.current_view.update):
                    self.current_view.update()


        def handle_global_input(self, key):
            if key == 27: # ESC key (usually) or q for quit
                 self.running = False
                 self.status_message = "Exiting AXLAP..."
            elif key == ord('q'): # For consistency with help message
                 self.running = False
                 self.status_message = "Exiting AXLAP..."
            elif key == ord('d') or key == ord('D'):
                self.current_view_name = "dashboard"
                self.current_view = self.views[self.current_view_name]
                self.status_message = "Switched to Dashboard View."
            elif key == ord('s') or key == ord('S'):
                self.current_view_name = "sessions"
                self.current_view = self.views[self.current_view_name]
                self.status_message = "Switched to Session Browser View."
            elif key == ord('p') or key == ord('P'):
                self.current_view_name = "plugins"
                self.current_view = self.views[self.current_view_name]
                self.status_message = "Switched to Plugin Manager View."
            elif key == ord('g') or key == ord('G'):
                self.current_view_name = "graph"
                self.current_view = self.views[self.current_view_name]
                self.status_message = "Switched to Correlation Graph View."
            elif key == curses.KEY_F1 or key == ord('h') or key == ord('H'): # Help
                self.show_help_popup()
            # Add other global shortcuts (e.g., F5 to refresh current view data)
            elif key == curses.KEY_F5:
                if hasattr(self.current_view, 'force_refresh_data'):
                    self.current_view.force_refresh_data()
                    self.status_message = f"{self.current_view_name.capitalize()} view data refreshed."
                else:
                    self.status_message = "This view does not support manual refresh (F5)."


        def show_help_popup(self):
            h, w = self.stdscr.getmaxyx()
            popup_h, popup_w = 15, 60
            popup_y = (h - popup_h) // 2
            popup_x = (w - popup_w) // 2
            
            help_win = curses.newwin(popup_h, popup_w, popup_y, popup_x)
            help_win.border()
            help_win.bkgd(' ', curses.color_pair(7) | curses.A_BOLD) # Inverse background

            help_win.addstr(1, (popup_w - len("AXLAP HELP")) // 2, "AXLAP HELP", curses.A_BOLD)
            
            help_text = [
                "Global Shortcuts:",
                "  D: Dashboard",
                "  Q: Query Panel (metadata search)",
                "  S: Session Browser (Arkime)",
                "  P: Plugin Manager (Zeek)",
                "  G: Correlation Graph (OpenCTI)",
                "  H or F1: This Help Screen",
                "  F5: Refresh current view's data",
                "  ESC or q: Quit AXLAP",
                "",
                "Navigation within views:",
                "  Arrow Keys, TAB, Enter (view specific)",
                "",
                "Press any key to close this help popup."
            ]
            
            for i, line in enumerate(help_text):
                help_win.addstr(i + 3, 2, line[:popup_w-4])

            help_win.refresh()
            self.stdscr.nodelay(False) # Blocking getch for popup
            help_win.getch()
            self.stdscr.nodelay(True) # Restore non-blocking
            # self.stdscr.touchwin() # Force redraw of underlying screen
            # self.stdscr.refresh()
            # A full redraw on next loop iteration will handle this.


def main(stdscr):
        # For debugging Curses apps, wrap in try-except to restore terminal
        try:
            app = AXLAPTUI(stdscr)
            app.run()
        except Exception as e:
            # Clean up curses
            curses.nocbreak()
            stdscr.keypad(False)
            curses.echo()
            curses.endwin()
            print("Error in AXLAP TUI:", e)
            import traceback
            traceback.print_exc()
        finally:
            if not curses.isendwin(): # Ensure curses is ended if not already
                curses.nocbreak()
                stdscr.keypad(False)
                curses.echo()
                curses.endwin()


if __name__ == "__main__":
        # Check if running in a proper terminal
        if not os.isatty(0) or not os.isatty(1):
            print("AXLAP TUI must be run in a TTY (terminal).")
            print("For headless/SSH operation, ensure SSH client provides a TTY.")
            exit(1)
            
        curses.wrapper(main)
