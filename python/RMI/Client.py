
import os
import weakref
import pprint
import RMI.Client

class ForkedPipes(RMI.Client):
    def __init__(self):
        (client_reader, server_writer) = os.pipe()
        (server_reader, client_writer) = os.pipe()

        if not os.fork():
            # the child process starts a server and exits when done
            RMI.DEBUG_MSG_PREFIX = '    SERVER'
            #RMI.DEBUG_FLAG = 1
            server_reader = os.fdopen(server_reader, 'r')
            server_writer = os.fdopen(server_writer, 'w')
            s = RMI.Node(reader = server_reader, writer = server_writer)

            # the server should return fals whenever a client disconnects
            # somehow it just hangs :( 
            # we need to fix this
            response = s.receive_request_and_send_response()
            while (response):
                if response[3] == 'exitnow':
                    response = None
                else:
                    response = s.receive_request_and_send_response()
            print("SERVER DONE")
            exit()

        else:
            # the parent process initializes as the client and continues
            RMI.DEBUG_MSG_PREFIX = 'CLIENT'
            #RMI.DEBUG_FLAG = 1 
            client_reader = os.fdopen(client_reader, 'r')
            client_writer = os.fdopen(client_writer, 'w')
            RMI.Client.__init__(self,client_reader,client_writer)
