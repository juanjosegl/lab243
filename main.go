package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"mensaje": "Imagen segura construida en pipeline",
			"version": "1.0.0",
		})
	})

	log.Println("Servidor escuchando en puerto " + port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
