package com.vxcommerce.storebff.downstream;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.web.reactive.server.WebTestClient;
import org.springframework.web.reactive.function.client.ClientRequest;
import org.springframework.web.reactive.function.client.ClientResponse;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

class DownstreamControllerTest {

    @Test
    void callsTheApiWithTheSubscriptionKey() {
        AtomicReference<ClientRequest> sent = new AtomicReference<>();
        WebClient stub = WebClient.builder()
                .baseUrl("https://apim.example.net/orders-api")
                .defaultHeader("Ocp-Apim-Subscription-Key", "test-key")
                .exchangeFunction(request -> {
                    sent.set(request);
                    return Mono.just(ClientResponse.create(HttpStatus.OK)
                            .header(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                            .body("{\"status\":\"ok\",\"service\":\"orders-api\"}")
                            .build());
                })
                .build();

        client(stub).get().uri("/downstream/health")
                .exchange()
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.service").isEqualTo("store-bff")
                .jsonPath("$.api.service").isEqualTo("orders-api");

        assertThat(sent.get().url().toString()).isEqualTo("https://apim.example.net/orders-api/health");
        assertThat(sent.get().headers().getFirst("Ocp-Apim-Subscription-Key")).isEqualTo("test-key");
    }

    @Test
    void returnsBadGatewayWhenTheApiFails() {
        WebClient failing = WebClient.builder()
                .exchangeFunction(request -> Mono.just(ClientResponse.create(HttpStatus.UNAUTHORIZED).build()))
                .build();

        client(failing).get().uri("/downstream/health")
                .exchange()
                .expectStatus().isEqualTo(HttpStatus.BAD_GATEWAY)
                .expectBody()
                .jsonPath("$.error").exists();
    }

    private static WebTestClient client(WebClient apiWebClient) {
        return WebTestClient
                .bindToController(new DownstreamController(new DownstreamApiClient(apiWebClient), "store-bff"))
                .build();
    }
}
