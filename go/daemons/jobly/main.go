package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net"
	"os"
	"syscall"
	"time"

	redis "github.com/xuyu/goredis"
)

type Work struct {
	user, command string
}

func RunUpdateHook(box string) {

	const MEAN = 5
	const TIMEOUT = 5 * time.Second

	log.Println("Executing ", box)

	done := make(chan struct{})
	cancelled := false

	go func() {
		time.Sleep(1*time.Second + time.Duration(1e9*rand.ExpFloat64()*MEAN))
		close(done)
		if !cancelled {
			log.Println("  Completed ", box)
		}
	}()

	// cmd := exec.Command(work.command)
	// cmd.Start()
	// go func() {
	// 	cmd.Wait()
	// 	close(done)
	// }()

	select {
	case <-done:
		return

	case <-time.After(TIMEOUT):
		cancelled = true
		log.Println("  Cancelled ", box)
		// cmd.Process.Kill()
	}
}

func Worker(boxQ <-chan string) {
	for box := range boxQ {
		log.Printf("qLen = %v", len(boxQ))
		RunUpdateHook(box)
	}
}

func check(err error) {
	if err != nil {
		panic(err)
	}
}

type Message struct {
	Boxes   []string `json:"boxes"`
	Message string   `json:"message"`
	Origin  struct {
		Box     string `json:"box"`
		BoxJSON struct {
			Database     string `json:"database"`
			PublishToken string `json:"publish_token"`
		} `json:"boxJSON"`
		BoxServer          string `json:"boxServer"`
		CreatedDate        string `json:"createdDate"`
		CreatorDisplayName string `json:"creatorDisplayName"`
		CreatorShortName   string `json:"creatorShortName"`
		DisplayName        string `json:"displayName"`
		Tool               string `json:"tool"`
		User               string `json:"user"`
		Views              []struct {
			ID      string `json:"_id"`
			Box     string `json:"box"`
			BoxJSON struct {
				Database     string `json:"database"`
				PublishToken string `json:"publish_token"`
			} `json:"boxJSON"`
			BoxServer   string `json:"boxServer"`
			DisplayName string `json:"displayName"`
			State       string `json:"state"`
			Tool        string `json:"tool"`
		} `json:"views"`
	} `json:"origin"`
	Type string `json:"type"`
}

func Exists(path string) bool {
	_, err := os.Stat(path)
	return err != nil
}

func UpdatePath(box string) string {
	return fmt.Sprintf("/var/lib/cobalt/home/%s/tool/hooks/update", box)
}

func UpdateHookExists(box string) bool {
	return Exists(UpdatePath(box))
}

func main() {
	const N_WORKERS = 4

	url := os.ExpandEnv("tcp://auth:${REDIS_PASSWORD}@${REDIS_SERVER}:6379/0?timeout=10s&maxidle=1")
	client, err := redis.DialURL(url)

	switch err := err.(type) {
	case *net.OpError:
		if err.Err.Error() == "connection refused" {
			log.Fatal("Connection refused. Aborting.")
		}
	}
	// if syscall.ECONNREFUSED.

	e := err.(*net.OpError).Err.(syscall.Errno)
	log.Println("conn:", e.Temporary(), e.Timeout(), e.Error())

	check(err)

	workQ := make(chan string, 100)

	for i := 0; i < N_WORKERS; i++ {
		go Worker(workQ)
	}

	pubsub, err := client.PubSub()
	check(err)

	err = pubsub.PSubscribe("production.cobalt.*")
	check(err)

	for {
		result, err := pubsub.Receive()
		check(err)

		event := result[0]

		if event != "pmessage" {
			continue
		}
		pattern, match, payload := result[1], result[2], result[3]

		_, _ = pattern, match

		m := &Message{}
		err = json.Unmarshal([]byte(payload), &m)
		if err != nil {
			log.Printf("Failed to unmarshal payload %q", err)
			continue
		}

		// log.Println(result)
		log.Printf("update hook boxes: %q", m.Boxes)

		for _, box := range m.Boxes {
			if !UpdateHookExists(box) {
				continue
			}
			log.Printf("qLen = %v", len(workQ))
			workQ <- box
		}
	}

	// for work := range ReadFromRedisQ() {
	// 	workQ <- work
	// }
}
