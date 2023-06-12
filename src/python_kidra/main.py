import cherrypy
import python_kidra.text_statistics as text_statistics


class WebService:
    @cherrypy.expose
    def _ping(self):
        pass

    @cherrypy.expose
    @cherrypy.tools.json_in()
    @cherrypy.tools.json_out()
    def analyze_text(self):
        return text_statistics.analyze_text(cherrypy.request.json)


def main():
    # listen to requests from any incoming IP address
    cherrypy.server.socket_host = "0.0.0.0"
    cherrypy.quickstart(WebService())


if __name__ == "__main__":
    main()
