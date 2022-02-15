NAME := Claw

VERSION ?= $(shell awk '$$2 == "Version:" { print $$3; exit }' "$(NAME).toc")

ZIP := $(NAME)_$(VERSION).zip

FILES := *.toc *.lua *.xml *.blp LICENSE

PREFIX ?= /media/wow-addons

all: $(ZIP)

$(ZIP): $(NAME)
	@echo "Creating ZIP: $(ZIP)"
	@zip -r9 "$@" "$(NAME)"

$(NAME):
	@echo "Creating AddOn folder: $(NAME)"
	@mkdir "$(NAME)"
	@cp -r $(FILES) "$(NAME)"

install: $(ZIP)
	@echo "Installing (extracting) ZIP: $(ZIP)"
	@unzip -o "$(ZIP)" -d "$(PREFIX)"

uninstall:
	@echo "Uninstalling AddOn: $(NAME)"
	@rm -rvf "$(PREFIX)/$(NAME)"

prefixcopy:
	@echo "Overwriting with files from AddOn folder: $(NAME)"
	@cp -rT "$(PREFIX)/$(NAME)" .

clean:
	@rm -vf "$(NAME)_"*.zip*
	@rm -rvf "$(NAME)"
	@echo "Done."
