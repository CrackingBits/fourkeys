DOCKER_COMPOSE = docker-compose --project-directory ../ -f docker-compose.yml
export WEBHOOK = http://0.0.0.0:8080
export SECRET = apisecret

clean:
	@$(DOCKER_COMPOSE) rm -savf $(c)

build-and-up:
	@$(DOCKER_COMPOSE) up --build $(c)

restart: clean build-and-up

status: ## Show status of containers
	@$(DOCKER_COMPOSE) ps

prepare-push-endpoint:
	curl -s -H "Authorization: Bearer ACCESS_TOKEN_NOT_NECESSARY" -X PUT "http://localhost:8432/v1/projects/fourkeys-pubsub/topics/github" && \
	curl -s -H "Authorization: Bearer ACCESS_TOKEN_NOT_NECESSARY" -X PUT "http://localhost:8432/v1/projects/fourkeys-pubsub/subscriptions/mysub" \
		-H "Content-Type: application/json" \
		--data "{'topic':'projects/fourkeys-pubsub/topics/github','pushConfig':{'pushEndpoint':'http://github-parser:8082/'}}"

generate-data:
	python3 ../data-generator/generate_data.py --vc_system=github
