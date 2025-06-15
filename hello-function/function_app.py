import azure.functions as func
import logging

app = func.FunctionApp()

@app.function_name(name="HelloWorld")
@app.route(route="hello")
def hello_world(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')
    return func.HttpResponse("Hello, world!", status_code=200)
