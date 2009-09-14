// This autogenerated skeleton file illustrates how to build a server.
// You should copy it to another filename to avoid overwriting it.

#include "AccessMethod.h"
#include <protocol/TBinaryProtocol.h>
#include <server/TSimpleServer.h>
#include <transport/TServerSocket.h>
#include <transport/TBufferTransports.h>

using namespace apache::thrift;
using namespace apache::thrift::protocol;
using namespace apache::thrift::transport;
using namespace apache::thrift::server;

using boost::shared_ptr;

using namespace DBToaster::Viewer::query20;

class AccessMethodHandler : virtual public AccessMethodIf {
 public:
  AccessMethodHandler() {
    // Your initialization goes here
  }

  int32_t get_var0() {
    // Your implementation goes here
    printf("get_var0\n");
  }

  int32_t get_var1() {
    // Your implementation goes here
    printf("get_var1\n");
  }

  void get_map0(std::map<int32_t, double> & _return) {
    // Your implementation goes here
    printf("get_map0\n");
  }

  void get_dom0(std::map<int32_t, int32_t> & _return) {
    // Your implementation goes here
    printf("get_dom0\n");
  }

  void get_asks(std::vector<asks_elem> & _return) {
    // Your implementation goes here
    printf("get_asks\n");
  }

  void get_map1(std::map<int32_t, int32_t> & _return) {
    // Your implementation goes here
    printf("get_map1\n");
  }

  void get_map2(std::map<int32_t, int32_t> & _return) {
    // Your implementation goes here
    printf("get_map2\n");
  }

  void get_var15(var15_tuple& _return) {
    // Your implementation goes here
    printf("get_var15\n");
  }

};

int main(int argc, char **argv) {
  int port = 9090;
  shared_ptr<AccessMethodHandler> handler(new AccessMethodHandler());
  shared_ptr<TProcessor> processor(new AccessMethodProcessor(handler));
  shared_ptr<TServerTransport> serverTransport(new TServerSocket(port));
  shared_ptr<TTransportFactory> transportFactory(new TBufferedTransportFactory());
  shared_ptr<TProtocolFactory> protocolFactory(new TBinaryProtocolFactory());

  TSimpleServer server(processor, serverTransport, transportFactory, protocolFactory);
  server.serve();
  return 0;
}

