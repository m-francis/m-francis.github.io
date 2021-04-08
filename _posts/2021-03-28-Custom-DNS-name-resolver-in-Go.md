---
author: mfrancis
title: Custom DNS Name Resolver in Go
---

Name resolution is arguably the most important function of DNS and is critical to the runtime of networking services.

Its main purpose is to allow humans to identify devices using memorable names, and to translate these names into numbers that computers can then use for routing across the network.

The most significant problem in name resolution is the frequency of requests it has to handle. This comes hand-in-hand with other concerns such as efficiency, caching, and reliability.

There is nothing magical about name resolvers themselves - they are clients interacting with servers. Anyone can implement their own client to interact with a name server. 

This is what I wanted to try out using Go.

<h2>What's there on Ubuntu?</h2>

Before moving on to an implementation of my custom name resolver let's look at the existing tooling available on Ubuntu. After all, my plan is not to replace any of the existing utilities but to better appreciate what they do.

There are a number of standard name resolvers available on Ubuntu and other types of distributions, for instance ```host```, `dig`, and `nslookup`. Let's try them out by querying the DNS resource records of this website.

<i>host</i>

<pre class="language-">
<code>$ host www.mfrancis.dev
www.mfrancis.dev is an alias for mfrancis.dev.
mfrancis.dev has address 151.101.65.195
mfrancis.dev has address 151.101.1.195</code>
</pre>

<i>dig</i>

<pre class="language-">
<code>$ dig +noall +answer www.mfrancis.dev
www.mfrancis.dev.	3011	IN	CNAME	mfrancis.dev.
mfrancis.dev.		3011	IN	A	    151.101.65.195
mfrancis.dev.		3011	IN	A	    151.101.1.195</code>
</pre>

<i>nslookup</i>

<pre class="language-">
<code>$ nslookup www.mfrancis.dev
Server:		127.0.0.53
Address:	127.0.0.53#53

Non-authoritative answer:
www.mfrancis.dev	canonical name = mfrancis.dev.
Name:	mfrancis.dev
Address: 151.101.65.195
Name:	mfrancis.dev
Address: 151.101.1.195</code>
</pre>

I prefer `host` due to its sweet and simple nature, although `dig` is the more elaborate one. For instance, using `dig` we can do reverse lookups:

<pre class="language-">
<code>$ dig +noall +answer -x 185.199.109.153
153.109.199.185.in-addr.arpa. 3600 IN	PTR	cdn-185-199-109-153.github.com.</code>
</pre>

By default all of these utilities rely on the nameserver(s) configured in `/etc/resolv.conf`. On Ubuntu:

<pre class="language-">
<code>$ grep nameserver /etc/resolv.conf 
nameserver 127.0.0.53</code>
</pre>

This local address directs to a name server service managed using systemd. We can see that by looking up what's listening on TCP/UDP port 53:

<pre class="language-">
<code>$ sudo netstat -tulnp | grep -E ":53 "
tcp  0  0 127.0.0.53:53  0.0.0.0:*  LISTEN  1422/systemd-resolv 
udp  0  0 127.0.0.53:53  0.0.0.0:*          1422/systemd-resolv</code>
</pre>

Instead of querying the local name server we could configure Ubuntu to go to an external service, for instance Google's DNS name servers (`8.8.8.8` and `8.8.4.4`).

To locate the actual authoritative name servers for a domain we could use `whois` or `host -C` (which also resolves the IP):

<pre class="language-">
<code>$ host -C mfrancis.dev
Nameserver 216.239.34.106:
	mfrancis.dev has SOA record ns-cloud-a1.googledomains.com. cloud-dns-hostmaster.google.com. 23 21600 3600 259200 300
Nameserver 216.239.38.106:
	mfrancis.dev has SOA record ns-cloud-a1.googledomains.com. cloud-dns-hostmaster.google.com. 23 21600 3600 259200 300
Nameserver 216.239.32.106:
	mfrancis.dev has SOA record ns-cloud-a1.googledomains.com. cloud-dns-hostmaster.google.com. 23 21600 3600 259200 300
Nameserver 216.239.36.106:
	mfrancis.dev has SOA record ns-cloud-a1.googledomains.com. cloud-dns-hostmaster.google.com. 23 21600 3600 259200 300</code>
</pre>

These name servers will happily resolve requests for the `.dev` domain but reject everything else because they are the authority only for `.dev`.

<pre class="language-">
<code>$ host mfrancis.dev 216.239.34.106
Using domain server:
Name: 216.239.34.106
Address: 216.239.34.106#53
Aliases: 

mfrancis.dev has address 151.101.65.195
mfrancis.dev has address 151.101.1.195</code>
</pre>

<pre class="language-">
<code>$ host google.com 216.239.34.106
Using domain server:
Name: 216.239.34.106
Address: 216.239.34.106#53
Aliases: 

Host google.com not found: 5(REFUSED)</code>
</pre>

In addition to querying the configured name servers these tools also examine `/etc/hosts` which is an artifact of the host table name system. This is great for a basic name system on a small or local network (such as my Raspberry Pi stack) for static IP addresses. It also defines `localhost`.

<pre class="language-">
<code>$ head -n6 /etc/hosts
127.0.0.1       localhost
127.0.1.1       mubuntu
192.168.1.120   queen
192.168.1.121   worker1
192.168.1.122   worker2
192.168.1.123   worker3</code>
</pre>

<h2>Writing a DNS name resolver</h2>

Even though this is a playground implementation there are a couple of things I want to learn by doing this:
<ul>
<li>The protocol of DNS name resolution</li>
<li>How to send and receive a UDP packet in Go</li>
<li>How to do bitwise operations in Go</li>
</ul>
I'm going to walk through my implementation using a top-down approach. The entire code can be found in my public GitHub repository.

Once the repository is cloned, to resolve a name using my implementation we can just run it and pass in the name. As you can see, this is similar to the output of `host.`

<pre class="language-">
<code>$ go run examples/dns/dns.go -name www.mfrancis.dev
www.mfrancis.dev. is an alias for mfrancis.dev.
mfrancis.dev. has address 151.101.1.195
mfrancis.dev. has address 151.101.65.195</code>
</pre>

The code defaults to one of the Google DNS name servers (`8.8.8.8`). To use a specific name server we can use the `-ns` flag.

The `main` function shown below prepares the query(-ies) we want to make (well, only one as I'll explain further down). I'm looking for only A type records.

<pre class="language-go">
<code>func main() {
	var ns = flag.String("ns", "8.8.8.8", "DNS Name Server")
	flag.Var(&namesFlag, "name", "name to resolve")

	flag.Parse()

	if len(namesFlag) == 0 {
		log.Fatal("name must be provided")
	}

	var qns []*dns.Question

	for _, name := range namesFlag {
		qns = append(qns, &dns.Question{
			QName:  name,
			QType:  dns.TypeA,
			QClass: dns.ClassInternet,
		})
	}

	msg := dns.LookupName(*ns, qns)
	printAnswers(msg)
}</code>
</pre>

The protocol for name resolution provides an option to ask the name server multiple questions in one query, although, I was surprised to learn, in practice this is not the case. The reason is primarily due to the ambiguous nature of flags in the protocol message format. What's mildly interesting is the different choices that implementors have made with regards to messages with multiple questions. For instance, Google name servers will happily provide an answer to the first question:

<pre class="language-">
<code>$ go run examples/dns/dns.go -ns 8.8.8.8 -name www.google.com -name www.mfrancis.dev
www.google.com. has address 172.217.194.104
www.google.com. has address 172.217.194.105
www.google.com. has address 172.217.194.99
www.google.com. has address 172.217.194.103
www.google.com. has address 172.217.194.106
www.google.com. has address 172.217.194.147</code>
</pre>

Whereas Ubuntu's name resolver will hang indefinitely (the timeout of 2s is set in my code):

<pre class="language-">
<code>$ go run examples/dns/dns.go -ns 127.0.0.53 -name www.google.com -name mfrancis.dev
2021/03/27 10:37:40 read udp 127.0.0.1:37738->127.0.0.53:53: i/o timeout
exit status 1</code>
</pre>

...but it will happily succeed if just one question is asked:

<pre class="language-">
<code>$ go run examples/dns/dns.go -ns 127.0.0.53 -name www.google.com 
www.google.com. has address 172.217.194.105
www.google.com. has address 172.217.194.104
www.google.com. has address 172.217.194.106
www.google.com. has address 172.217.194.147
www.google.com. has address 172.217.194.99
www.google.com. has address 172.217.194.103</code>
</pre>

Given the question(s) to ask we construct a message, send it off, and then handle the response. Messages are sent unicast (device to device). Name servers listen on port 53 whereas we, the client, use an ephemeral port number - Go makes it easy for us to receive the message back. Both the request and response messages have the same format.

The purpose of the `ID` field is to allow the caller to match up with the response in case it's making multiple calls; `RD` tells the name server that we desire recursive name resolution; `QDCount` is the number of questions in the message. The rest of the flags in the header are left to their default (0) values.

<pre class="language-go">
<code>func LookupName(nameserver string, qns []*Question) *Message {
	msg := Message{
		Header: &Header{
			ID:      uint16(rand.Int()),
			RD:      1,
			QDCount: uint16(len(qns)),
		},
		Questions: qns,
	}

	rb := sendAndReceiveMessage(nameserver, msg.ToWire())

	return NewMessageFromResponseBytes(rb)
}</code>
</pre>

We set deadlines to both sending and receiving bytes on the connection so we're not left hanging indefinitely. Otherwise the code is rather self-explanatory.

<pre class="language-go">
<code>const (
	WriteTimeout = 2 * time.Second
	ReadTimeout  = 2 * time.Second
)

func sendAndReceivePacket(nameserver string, reqB []byte) []byte {
	conn, err := net.Dial("udp", fmt.Sprintf("%s:53", nameserver))

	if err != nil {
		log.Fatal(err)
	}

	defer conn.Close()

	conn.SetWriteDeadline(time.Now().Add(WriteTimeout))

	if _, err := conn.Write(reqB); err != nil {
		log.Fatal(err)
	}

	conn.SetReadDeadline(time.Now().Add(ReadTimeout))

	rb := make([]byte, 512)

	if _, err := conn.Read(rb); err != nil {
		log.Fatal(err)
	}

	return rb
}</code>
</pre>

The most interesting part in this code is the `msg.ToWire()` function which is responsible for constructing the message in wire format.

The request message to the name server needs two sections: Header and Question(s), hence:

<pre class="language-go">
<code>func (m *Message) ToWire() []byte {
	var msg []byte

	msg = append(msg, m.Header.ToWire()...)

	for _, qn := range m.Questions {
		msg = append(msg, qn.ToWire()...)
	}

	return msg
}</code>
</pre>

I'm just going to look at constructing the bytes for the Header because it's the one that involves bitwise operations.

I'm using a `struct` to represent it:

<pre class="language-go">
<code>type Header struct {
	ID           uint16
	QR           uint8
	OpCode       uint8
	AA           uint8
	TC           uint8
	RD           uint8
	RA           uint8
	Z            uint8
	RCode        uint8
	QDCount      uint16
	ANCount      uint16
	NSCount      uint16
	ARCount      uint16
}</code>
</pre>

We define the sizes in bits/bytes for each value in the Header as constants which will simplify the operations:

<pre class="language-go">
<code>const (
	bytesInID      = 2
	bitsInQR       = 1
	bitsInOpCode   = 4
	bitsInAA       = 1
	bitsInTC       = 1
	bitsInRD       = 1
	bitsInRA       = 1
	bitsInZ        = 3
	bitsInRCode    = 4
	bytesInQDCount = 2
	bytesInANCount = 2
	bytesInNSCount = 2
	bytesInARCount = 2
)</code>
</pre>

All that's left is construction, one byte at a time.

We need to convert the `ID` field into two bytes, so we shift the bits right by 8 places to get the 8 most significant bits into the first byte. We then apply a bitmask to extract the 8 least significant bits and ensure we do not overflow.

Following that we do some bitwise operation magic with masking and shifting. In essence, we insert N bits into a byte and then shift them left to accommodate the next set of bits until we're done with the byte.

I don't find bitwise operations intuitive so if you're like me I recommend opening up a Go playground session and just trying it out.

<pre class="language-go">
<code>func (h *Header) ToWire() []byte {
	header := []byte{uint8(h.ID >> 8), uint8(h.ID & 0xff)}

	var oneByte uint8

	oneByte = h.QR & (1<<bitsInQR - 1)
	oneByte <<= bitsInOpCode
	oneByte |= h.OpCode & (1<<bitsInOpCode - 1)
	oneByte <<= bitsInAA
	oneByte |= h.AA & (1<<bitsInAA - 1)
	oneByte <<= bitsInTC
	oneByte |= h.TC & (1<<bitsInTC - 1)
	oneByte <<= bitsInRD
	oneByte |= h.RD & (1<<bitsInRD - 1)
	header = append(header, oneByte)

	oneByte = h.RA & (1<<bitsInRA - 1)
	oneByte <<= bitsInZ
	oneByte |= h.Z & (1<<bitsInZ - 1)
	oneByte <<= bitsInRCode
	oneByte |= h.RCode & (1<<bitsInRCode - 1)
	header = append(header, oneByte)

	twoBytes := make([]byte, 2) // we know they are 16 bit ints

	binary.BigEndian.PutUint16(twoBytes, h.QDCount)
	header = append(header, twoBytes...)

	binary.BigEndian.PutUint16(twoBytes, h.ANCount)
	header = append(header, twoBytes...)

	binary.BigEndian.PutUint16(twoBytes, h.NSCount)
	header = append(header, twoBytes...)

	binary.BigEndian.PutUint16(twoBytes, h.ARCount)
	header = append(header, twoBytes...)

	return header
}</code>
</pre>

The same process, albeit in reverse, can be applied to extract the flags out of a byte.

<pre class="language-go">
<code>func NewHeaderFromResponseBytes(rb []byte) *Header {
	h := Header{}

	h.ID = binary.BigEndian.Uint16(rb[:bytesInID])
	offset := bytesInID

	oneByte := rb[offset]
	h.RD = oneByte & (1<<bitsInRD - 1)
	oneByte >>= bitsInRD
	h.TC = oneByte & (1<<bitsInTC - 1)
	oneByte >>= bitsInTC
	h.AA = oneByte & (1<<bitsInAA - 1)
	oneByte >>= bitsInAA
	h.OpCode = oneByte & (1<<bitsInOpCode - 1)
	oneByte >>= bitsInOpCode
	h.QR = oneByte & (1<<bitsInQR - 1)
	offset += 1

	oneByte = rb[offset]
	h.RCode = oneByte & (1<<bitsInRCode - 1)
	oneByte >>= bitsInRCode
	h.Z = oneByte & (1<<bitsInZ - 1)
	oneByte >>= bitsInZ
	h.RA = oneByte & (1<<bitsInRA - 1)
	offset += 1

	h.QDCount = binary.BigEndian.Uint16(rb[offset : offset+bytesInQDCount])
	offset += bytesInQDCount

	h.ANCount = binary.BigEndian.Uint16(rb[offset : offset+bytesInANCount])
	offset += bytesInANCount

	h.NSCount = binary.BigEndian.Uint16(rb[offset : offset+bytesInNSCount])
	offset += bytesInNSCount

	h.ARCount = binary.BigEndian.Uint16(rb[offset : offset+bytesInARCount])
	offset += bytesInARCount

	return &h
}</code>
</pre>

Doing bitwise operations can be scary, so to help ensure we're doing the right things I've defined unit tests that ensure `ToWire()` and `NewHeaderFromResponseBytes` are symmetric.

I'm using table-driven tests which is a great, natural feature of testing in GO.

<pre class="language-go">
<code>func TestHeader(t *testing.T) {
	testCases := []struct {
		name   string
		header dns.Header
		rb     []byte
	}{
		{
			name:   "every value at its minimum",
			header: dns.Header{},
			rb:     []byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name: "every value at its maximum",
			header: dns.Header{
				ID:      ^uint16(0),
				QR:      1,
				OpCode:  15,
				AA:      1,
				TC:      1,
				RD:      1,
				RA:      1,
				Z:       7,
				RCode:   15,
				QDCount: ^uint16(0),
				ANCount: ^uint16(0),
				NSCount: ^uint16(0),
				ARCount: ^uint16(0),
			},
			rb: []byte{255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
		},
		{
			name:   "ID is on",
			header: dns.Header{ID: uint16(9999)},
			rb:     []byte{39, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name:   "QR is on",
			header: dns.Header{QR: 1},
			rb:     []byte{0, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name:   "OpCode is on",
			header: dns.Header{OpCode: 10},
			rb:     []byte{0, 0, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name:   "AA is on",
			header: dns.Header{AA: 1},
			rb:     []byte{0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name:   "TC is on",
			header: dns.Header{TC: 1},
			rb:     []byte{0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name:   "RD is on",
			header: dns.Header{RD: 1},
			rb:     []byte{0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name:   "RA is on",
			header: dns.Header{RA: 1},
			rb:     []byte{0, 0, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name:   "Z is on",
			header: dns.Header{Z: 7},
			rb:     []byte{0, 0, 0, 112, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name:   "RCode is on",
			header: dns.Header{RCode: 7},
			rb:     []byte{0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0},
		},
		{
			name:   "QDCount is on",
			header: dns.Header{QDCount: 2},
			rb:     []byte{0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0},
		},
		{
			name:   "ANCount is on",
			header: dns.Header{ANCount: 2},
			rb:     []byte{0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0},
		},
		{
			name:   "NSCount is on",
			header: dns.Header{NSCount: 2},
			rb:     []byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0},
		},
		{
			name:   "ARCount is on",
			header: dns.Header{ARCount: 2},
			rb:     []byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2},
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			wire := tc.header.ToWire()
			if bytes.Compare(wire, tc.rb) != 0 {
				t.Fatalf("Header wire format mismatch (expected %v got %v)", tc.rb, wire)
			}
			header := dns.NewHeaderFromResponseBytes(tc.rb)
			if !reflect.DeepEqual(header, &tc.header) {
				t.Fatalf("Headers do not match (expected %v got %v)", tc.header, header)
			}
		})
	}
}</code>
</pre>

Another interesting part of the DNS name resolution protocol is name compaction. The intent is to limit byte repetition in messages hence save on the payload size.

Given the response bytes and the offset at which the name begins we can extract it like this:

<pre class="language-go">
<code>func DecompressName(rb []byte, offset uint16) (name string, nb uint16) {
	byteAtOffset := uint8(rb[offset])

	if byteAtOffset == 0 { // root of the name hierarchy
		return "", 1
	}

	if byteAtOffset >= 192 { // compressed; pointer is two bytes
		ptrOffset := binary.BigEndian.Uint16([]byte{
			uint8(byteAtOffset & (1<<6 - 1)), // trailing 6 bits of the first byte
			rb[offset+1],                     // the second byte
		})
		name, _ := DecompressName(rb, ptrOffset)
		return name, 2
	}

	labelLength := byteAtOffset

	labelStartInd := offset + 1
	labelEndInd := labelStartInd + uint16(labelLength)
	label := fmt.Sprintf("%s.", string(rb[labelStartInd:labelEndInd]))

	restOfName, restOfLength := DecompressName(rb, labelEndInd)

	name = label + restOfName
	nb = 1 + uint16(labelLength) + restOfLength

	return
}</code>
</pre>

...and of course we need some tests to make sure:

<pre class="language-go">
<code>func TestDecompressName(t *testing.T) {
	testCases := []struct {
		desc   string
		rb     []byte
		offset uint16
		name   string
		length uint16
	}{
		{
			desc:   "one label, uncompressed",
			rb:     []byte{3, 119, 119, 119, 0},
			offset: 0,
			name:   "www.",
			length: 5,
		},
		{
			desc:   "full name, uncompressed",
			rb:     []byte{3, 119, 119, 119, 8, 109, 102, 114, 97, 110, 99, 105, 115, 3, 100, 101, 118, 0},
			offset: 0,
			name:   "www.mfrancis.dev.",
			length: 18,
		},
		{
			desc:   "full name is a pointer",
			rb:     []byte{3, 119, 119, 119, 8, 109, 102, 114, 97, 110, 99, 105, 115, 3, 100, 101, 118, 0, 192, 0},
			offset: 18,
			name:   "www.mfrancis.dev.",
			length: 2,
		},
		{
			desc:   "subset of name is a pointer",
			rb:     []byte{8, 109, 102, 114, 97, 110, 99, 105, 115, 3, 100, 101, 118, 0, 3, 119, 119, 119, 192, 0},
			offset: 14,
			name:   "www.mfrancis.dev.",
			length: 6,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.desc, func(t *testing.T) {
			name, length := dns.DecompressName(tc.rb, tc.offset)
			if name != tc.name {
				t.Fatalf("name does not match (expected %s was %s)", tc.name, name)
			}
			if length != tc.length {
				t.Fatalf("length does not match (expected %d was %d)", tc.length, length)
			}
		})
	}
}
</code>
</pre>

<h2>Summary</h2>

This post used `host`, `dig`, `nslookup`, and `whois` to interact with the world's DNS. We then wrote a small application that let's us query a name server of our choice to lookup the DNS resource records for a given name. We saw that DNS name server implementations can wary. The code has been written in Go and includes test cases for some of the more elaborate functions.
