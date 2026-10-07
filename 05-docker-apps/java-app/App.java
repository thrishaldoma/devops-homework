import com.sun.net.httpserver.HttpServer;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.InetAddress;

public class App {
    public static void main(String[] args) throws Exception {
        int port = 8080;
        HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);
        server.createContext("/", exchange -> {
            String host = InetAddress.getLocalHost().getHostName();
            String body = "<html><head><title>Java + Docker</title></head>"
                + "<body style='font-family:sans-serif;text-align:center;padding-top:60px'>"
                + "<h1>Hello World from Java + Docker!</h1>"
                + "<p>Container hostname: " + host + "</p>"
                + "<p>Java version: " + System.getProperty("java.version") + "</p>"
                + "</body></html>";
            byte[] bytes = body.getBytes("UTF-8");
            exchange.getResponseHeaders().set("Content-Type", "text/html; charset=utf-8");
            exchange.sendResponseHeaders(200, bytes.length);
            OutputStream os = exchange.getResponseBody();
            os.write(bytes);
            os.close();
        });
        server.setExecutor(null);
        server.start();
        System.out.println("Java server running on port " + port);
    }
}
