local template = require("resty.template")

content = {
	message = "hello template",
	names = {"paprikaLang","tiyo"}
}

template.render("demo.html", content)