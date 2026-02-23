.PHONY: docker clean

# Build both variants via Docker
docker:
	docker buildx build --output=out .

clean:
	rm -rf out/ build/ sources/ vcpkg_installed/
