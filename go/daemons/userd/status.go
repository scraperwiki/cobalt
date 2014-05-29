package main

import (
	"fmt"
	"time"
)

type StatusValue struct {
	NFailure, NSuccess       uint64
	LastSuccess, LastFailure time.Time
}

func (s StatusValue) Json() string {
	return fmt.Sprintf(
		JSON_STATUS_TIME,
		s.NSuccess, s.LastSuccess, time.Since(s.LastSuccess),
		s.NFailure, s.LastFailure, time.Since(s.LastFailure))
}

type Status struct {
	Success, Failure chan struct{}    // Update
	Read             chan StatusValue // Read

	StatusValue
}

func NewStatus() *Status {
	s := &Status{
		Success: make(chan struct{}),
		Failure: make(chan struct{}),
		Read:    make(chan StatusValue),
	}

	go func() {
		for {
			select {
			case s.Success <- struct{}{}:
				s.LastSuccess = time.Now()
				s.NSuccess++
			case s.Failure <- struct{}{}:
				s.LastFailure = time.Now()
				s.NFailure++

			case s.Read <- s.StatusValue:
				// Empty case sends s.StatusValue by value at time of write.
			}
		}
	}()
	return s
}
