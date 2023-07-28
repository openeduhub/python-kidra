import cherrypy
from python_kidra.webservice import Service, KidraService

# the collection of all services to be collected in the kidra
SERVICES: set[Service] = {
    Service(
        name="text-statistics",
        binary="text-statistics",
        host="localhost",
        port="19867",
        post_subdomain="analyze-text",
    ),
}


def main():
    # listen to requests from any incoming IP address
    cherrypy.server.socket_host = "0.0.0.0"
    webservice = KidraService(SERVICES)
    cherrypy.quickstart(webservice)


if __name__ == "__main__":
    main()
